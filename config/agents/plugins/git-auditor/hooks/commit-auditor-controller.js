"use strict";

const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");
const { sanitizeToAscii } = require(path.join(__dirname, "lib"));

const CODEX_REQUIRED_ENV = [
    "CODEX_THREAD_ID",
    "CODEX_CTL_GATE_ENDPOINT",
    "CODEX_CTL_GATE_TOKEN",
    "CODEX_CTL_GENERATION_ID",
    "CODEX_CTL_GATE_PROTOCOL",
    "CODEX_CTL_EXECUTABLE",
    "CODEX_CTL_INSTANCE",
];
const CODEX_CAPABILITY_ENV = CODEX_REQUIRED_ENV.slice(1);
const OPENCODE_MARKER_ENV = [
    "OPENCODE_SERVER_URL",
    "OPENCODE_SESSION_ID",
    "OPENCODE_CALL_ID",
    "OPENCODE_PROJECT_DIR",
];

function present(env, key) {
    return typeof env[key] === "string" && env[key].trim() !== "";
}

function classifyRuntime(env = process.env) {
    const managedCodexPresent = CODEX_CAPABILITY_ENV.some((key) => present(env, key));
    const openCodePresent = OPENCODE_MARKER_ENV.some((key) => present(env, key));

    if (managedCodexPresent && openCodePresent) {
        return {
            kind: "invalid",
            reason: "mixed managed Codex and OpenCode runtime markers make the gate provider ambiguous",
        };
    }

    if (managedCodexPresent) {
        const missing = CODEX_REQUIRED_ENV.filter((key) => !present(env, key));
        if (missing.length > 0) {
            return {
                kind: "invalid",
                reason: `incomplete managed Codex gate environment; missing ${missing.join(", ")}`,
            };
        }
        if (env.CODEX_CTL_GATE_PROTOCOL !== "1") {
            return {
                kind: "invalid",
                reason: `unsupported managed Codex gate protocol ${JSON.stringify(env.CODEX_CTL_GATE_PROTOCOL)}`,
            };
        }
        return {
            kind: "codex",
            executable: env.CODEX_CTL_EXECUTABLE,
            generationId: env.CODEX_CTL_GENERATION_ID,
            instance: env.CODEX_CTL_INSTANCE,
            originThreadId: env.CODEX_THREAD_ID,
        };
    }

    if (openCodePresent) {
        if (!present(env, "OPENCODE_SERVER_URL")) {
            return {
                kind: "invalid",
                reason: "incomplete OpenCode audit environment; missing OPENCODE_SERVER_URL",
            };
        }
        return { kind: "opencode" };
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
    if (runtime.kind !== "codex") {
        throw new Error("managed gate commands require a Codex runtime");
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
