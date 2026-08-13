"use strict";

const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");
const { sanitizeToAscii } = require(path.join(__dirname, "lib"));

const GATE_REQUIRED_ENV = [
    "CODEX_CTL_GATE_ENDPOINT",
    "CODEX_CTL_GATE_TOKEN",
    "CODEX_CTL_GATE_PROTOCOL",
    "CODEX_CTL_EXECUTABLE",
    "CODEX_CTL_INSTANCE",
];
const RUNTIME_REQUIRED_ENV = [
    "CODEX_CTL_RUNTIME_KIND",
    "CODEX_CTL_RUNTIME_INSTANCE",
    "CODEX_CTL_SESSION_ID",
    "CODEX_CTL_WORKING_DIRECTORY",
];

function present(env, key) {
    return typeof env[key] === "string" && env[key].trim() !== "";
}

function classifyRuntime(env = process.env) {
    const managedPresent = GATE_REQUIRED_ENV.some((key) => present(env, key));
    if (managedPresent) {
        const protocol = env.CODEX_CTL_GATE_PROTOCOL;
        const required = protocol === "2"
            ? [...GATE_REQUIRED_ENV, ...RUNTIME_REQUIRED_ENV]
            : [...GATE_REQUIRED_ENV, "CODEX_CTL_GENERATION_ID", "CODEX_THREAD_ID"];
        const missing = required.filter((key) => !present(env, key));
        if (missing.length > 0) {
            return {
                kind: "invalid",
                reason: `incomplete managed gate environment; missing ${missing.join(", ")}`,
            };
        }
        if (!["1", "2"].includes(protocol)) {
            return {
                kind: "invalid",
                reason: `unsupported managed gate protocol ${JSON.stringify(protocol)}`,
            };
        }
        if (protocol === "2" && (present(env, "CODEX_THREAD_ID") || present(env, "CODEX_CTL_GENERATION_ID"))) {
            return {
                kind: "invalid",
                reason: "mixed generation and runtime gate markers are not allowed",
            };
        }
        return {
            kind: protocol === "1" ? "codex" : env.CODEX_CTL_RUNTIME_KIND,
            managed: true,
            executable: env.CODEX_CTL_EXECUTABLE,
            generationId: protocol === "1" ? env.CODEX_CTL_GENERATION_ID : null,
            instance: env.CODEX_CTL_INSTANCE,
            originThreadId: protocol === "1" ? env.CODEX_THREAD_ID : env.CODEX_CTL_SESSION_ID,
            runtimeInstanceId: protocol === "2" ? env.CODEX_CTL_RUNTIME_INSTANCE : null,
        };
    }
    return { kind: "local" };
}

function normalizeObjectId(value, field, { allowNull = false } = {}) {
    if (allowNull && value === null) return null;
    if (typeof value !== "string" || !/^[0-9a-f]{40}(?:[0-9a-f]{24})?$/u.test(value)) {
        throw new Error(`${field} must be a Git object ID`);
    }
    return value;
}

function normalizeAuditBinding(value) {
    if (!value || value.schemaVersion !== 1) {
        throw new Error("invalid audit binding schema");
    }
    if (value.headRef !== null && (typeof value.headRef !== "string" || !value.headRef.startsWith("refs/"))) {
        throw new Error("audit binding headRef must be a ref name or null");
    }
    return {
        schemaVersion: 1,
        baseCommit: normalizeObjectId(value.baseCommit, "audit binding baseCommit", { allowNull: true }),
        headRef: value.headRef,
        indexTree: normalizeObjectId(value.indexTree, "audit binding indexTree"),
    };
}

function validateCommitAuditBinding({ auditBinding, oldCommit, ref, tree, parents }) {
    const binding = normalizeAuditBinding(auditBinding);
    const expectedRef = binding.headRef || "HEAD";
    if (ref !== expectedRef) {
        throw new Error(`audited ref ${expectedRef} does not match transaction ref ${ref}`);
    }
    if (binding.baseCommit === null) {
        if (!/^0+$/u.test(oldCommit)) {
            throw new Error("the audited initial commit no longer has an unborn HEAD");
        }
        if (parents.length !== 0) {
            throw new Error("the final commit has parents but the audit saw an unborn HEAD");
        }
    } else {
        if (oldCommit !== binding.baseCommit) {
            throw new Error("HEAD changed after the commit message was audited");
        }
        if (parents[0] !== binding.baseCommit) {
            throw new Error(
                "the final commit does not descend from the audited HEAD; amend and replacement commits are unavailable in this managed runtime",
            );
        }
    }
    if (tree !== binding.indexTree) {
        throw new Error("the final commit tree differs from the index tree audited by commit-msg");
    }
    return binding;
}

function normalizeStructuredVerdict(value) {
    if (!value || typeof value !== "object") {
        throw new Error("gate result must be an object");
    }
    const result = value.result && typeof value.result === "object" ? value.result : value;
    const kind = typeof result.verdict === "string" ? result.verdict.toUpperCase() : "";
    if (!["APPROVE", "REWRITE", "REJECT"].includes(kind)) {
        throw new Error(`invalid verdict ${JSON.stringify(result.verdict)}`);
    }

    const rationale =
        typeof result.rationale === "string" && result.rationale.trim()
            ? result.rationale.trim()
            : null;
    const message =
        typeof result.message === "string" && result.message.trim()
            ? result.message.trim()
            : null;

    if (kind === "REWRITE" && !message) {
        throw new Error("REWRITE verdict requires a non-empty message");
    }
    if (kind === "REJECT" && !rationale) {
        throw new Error("REJECT verdict requires a non-empty rationale");
    }

    const verdict = { kind, rationale, message };
    if (result.infrastructureFailure === true) verdict.infrastructureFailure = true;
    return verdict;
}

function createInfrastructureReject(reason) {
    return {
        kind: "REJECT",
        rationale: `Commit gate infrastructure failed: ${reason}`,
        infrastructureFailure: true,
    };
}

async function applyVerdict(messagePath, verdict) {
    if (verdict.kind !== "REWRITE") {
        return { exitCode: verdict.kind === "REJECT" ? 1 : 0, changed: false };
    }

    const sanitized = await sanitizeToAscii(verdict.message);
    const message = sanitized.text.endsWith("\n") ? sanitized.text : `${sanitized.text}\n`;
    fs.writeFileSync(messagePath, message);
    return { exitCode: 0, changed: true };
}

function buildGateCommand(runtime, action, args = []) {
    if (!runtime.managed) {
        throw new Error("managed gate commands require a controller runtime");
    }
    return {
        command: process.execPath,
        args: [
            runtime.executable,
            "--instance",
            runtime.instance,
            "gate",
            action,
            ...args,
        ],
    };
}

function pendingReceiptPath(gitDir) {
    return path.join(gitDir, "codex-ctl-gate.pending.json");
}

function validateReceipt(receipt) {
    if (!receipt || receipt.schemaVersion !== 2) {
        throw new Error("invalid gate finalization receipt schema");
    }
    for (const key of [
        "gateId",
        "invocationId",
        "finalizationToken",
        "generationId",
        "originThreadId",
    ]) {
        if (typeof receipt[key] !== "string" || receipt[key].trim() === "") {
            throw new Error(`gate finalization receipt is missing ${key}`);
        }
    }
    return {
        ...receipt,
        auditBinding: normalizeAuditBinding(receipt.auditBinding),
    };
}

function writePendingReceipt(gitDir, receipt) {
    validateReceipt(receipt);
    const destination = pendingReceiptPath(gitDir);
    const temporary = `${destination}.${process.pid}.${crypto.randomUUID()}.tmp`;
    fs.writeFileSync(temporary, `${JSON.stringify(receipt)}\n`, { mode: 0o600 });
    fs.renameSync(temporary, destination);
}

function readPendingReceipt(gitDir) {
    const receiptPath = pendingReceiptPath(gitDir);
    if (!fs.existsSync(receiptPath)) return null;
    return validateReceipt(JSON.parse(fs.readFileSync(receiptPath, "utf8")));
}

function clearPendingReceipt(gitDir) {
    fs.rmSync(pendingReceiptPath(gitDir), { force: true });
}

module.exports = {
    applyVerdict,
    buildGateCommand,
    classifyRuntime,
    clearPendingReceipt,
    createInfrastructureReject,
    normalizeAuditBinding,
    normalizeStructuredVerdict,
    readPendingReceipt,
    validateCommitAuditBinding,
    writePendingReceipt,
};
