"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const { execFileSync } = require("node:child_process");
const os = require("node:os");
const path = require("node:path");
const test = require("node:test");

const {
    buildGateCommand,
    classifyRuntime,
    clearPendingReceipt,
    normalizeAuditBinding,
    normalizeStructuredVerdict,
    readPendingReceipt,
    validateCommitAuditBinding,
    writePendingReceipt,
} = require("./commit-auditor-controller");

const managedEnvironment = {
    CODEX_THREAD_ID: "thread-origin",
    CODEX_CTL_GATE_ENDPOINT: "http://127.0.0.1:49152",
    CODEX_CTL_GATE_TOKEN: "capability-token",
    CODEX_CTL_GENERATION_ID: "generation-4",
    CODEX_CTL_GATE_PROTOCOL: "1",
    CODEX_CTL_EXECUTABLE: "C:\\dev\\codex-ctl\\bin\\codex-ctl.mjs",
    CODEX_CTL_INSTANCE: "dev",
};

const runtimeManagedEnvironment = {
    CODEX_CTL_GATE_ENDPOINT: "http://127.0.0.1:14600/api/managed-gate",
    CODEX_CTL_GATE_TOKEN: "runtime-capability",
    CODEX_CTL_GATE_PROTOCOL: "2",
    CODEX_CTL_EXECUTABLE: "C:\\dev\\codex-ctl\\bin\\codex-ctl.mjs",
    CODEX_CTL_INSTANCE: "dev",
    CODEX_CTL_RUNTIME_KIND: "opencode",
    CODEX_CTL_RUNTIME_INSTANCE: "opencode-main",
    CODEX_CTL_SESSION_ID: "session-a",
    CODEX_CTL_WORKING_DIRECTORY: "C:\\work",
};

function runGit(directory, args) {
    return execFileSync("git", args, {
        cwd: directory,
        encoding: "utf8",
        stdio: ["ignore", "pipe", "pipe"],
    }).trim();
}

test("an unmanaged Codex thread remains in local policy mode", () => {
    assert.deepEqual(classifyRuntime({ CODEX_THREAD_ID: "thread-direct" }), {
        kind: "local",
    });
});

test("a complete managed capability identifies its generation and executable", () => {
    assert.deepEqual(classifyRuntime(managedEnvironment), {
        kind: "codex",
        managed: true,
        executable: managedEnvironment.CODEX_CTL_EXECUTABLE,
        generationId: "generation-4",
        instance: "dev",
        originThreadId: "thread-origin",
        runtimeInstanceId: null,
    });
});

test("a runtime-neutral capability identifies an OpenCode origin without provider credentials", () => {
    assert.deepEqual(classifyRuntime(runtimeManagedEnvironment), {
        kind: "opencode",
        managed: true,
        executable: runtimeManagedEnvironment.CODEX_CTL_EXECUTABLE,
        generationId: null,
        instance: "dev",
        originThreadId: "session-a",
        runtimeInstanceId: "opencode-main",
    });
    assert.deepEqual(
        buildGateCommand(classifyRuntime(runtimeManagedEnvironment), "invoke", ["git-commit"]),
        {
            command: process.execPath,
            args: [
                runtimeManagedEnvironment.CODEX_CTL_EXECUTABLE,
                "--instance",
                "dev",
                "gate",
                "invoke",
                "git-commit",
            ],
        },
    );
});

test("partial and mixed runtime markers fail closed", () => {
    const partial = classifyRuntime({
        CODEX_THREAD_ID: "thread-origin",
        CODEX_CTL_GATE_ENDPOINT: "http://127.0.0.1:49152",
    });
    assert.equal(partial.kind, "invalid");
    assert.match(partial.reason, /incomplete managed gate environment/);

    const mixed = classifyRuntime({
        ...runtimeManagedEnvironment,
        CODEX_THREAD_ID: "thread-origin",
    });
    assert.equal(mixed.kind, "invalid");
    assert.match(mixed.reason, /mixed generation and runtime gate markers/);
});

test("audit bindings tie the final commit to the audited base and index tree", () => {
    const baseCommit = "a".repeat(40);
    const indexTree = "b".repeat(40);
    const binding = normalizeAuditBinding({
        schemaVersion: 1,
        baseCommit,
        headRef: "refs/heads/main",
        indexTree,
    });

    assert.deepEqual(validateCommitAuditBinding({
        auditBinding: binding,
        oldCommit: baseCommit,
        ref: "refs/heads/main",
        tree: indexTree,
        parents: [baseCommit],
    }), binding);
    assert.throws(
        () => validateCommitAuditBinding({
            auditBinding: binding,
            oldCommit: baseCommit,
            ref: "refs/heads/main",
            tree: indexTree,
            parents: ["c".repeat(40)],
        }),
        /amend and replacement commits are unavailable/u,
    );
    assert.throws(
        () => validateCommitAuditBinding({
            auditBinding: binding,
            oldCommit: baseCommit,
            ref: "refs/heads/main",
            tree: "d".repeat(40),
            parents: [baseCommit],
        }),
        /tree differs/u,
    );
});

test("the hook invokes the exact injected controller and instance", () => {
    assert.deepEqual(buildGateCommand(classifyRuntime(managedEnvironment), "invoke", [
        "git-commit",
        "--json",
    ]), {
        command: process.execPath,
        args: [
            managedEnvironment.CODEX_CTL_EXECUTABLE,
            "--instance",
            "dev",
            "gate",
            "invoke",
            "git-commit",
            "--json",
        ],
    });
});

test("structured verdicts are read from the provider-neutral result envelope", () => {
    assert.deepEqual(
        normalizeStructuredVerdict({
            gateId: "git-commit",
            invocationId: "generation-4.invocation-1",
            result: {
                verdict: "rewrite",
                message: "[TEST] Exercise gate",
                rationale: "The original subject did not follow the convention.",
            },
        }),
        {
            kind: "REWRITE",
            message: "[TEST] Exercise gate",
            rationale: "The original subject did not follow the convention.",
        },
    );
});

test("a finalization receipt round-trips through Git metadata", (t) => {
    const gitDir = fs.mkdtempSync(path.join(os.tmpdir(), "codex-ctl-gate-receipt-"));
    t.after(() => fs.rmSync(gitDir, { recursive: true, force: true }));

    const receipt = {
        schemaVersion: 2,
        gateId: "git-commit",
        invocationId: "generation-4.invocation-1",
        finalizationToken: "one-time-token",
        generationId: "generation-4",
        originThreadId: "thread-origin",
        auditBinding: {
            schemaVersion: 1,
            baseCommit: "a".repeat(40),
            headRef: "refs/heads/main",
            indexTree: "b".repeat(40),
        },
    };
    writePendingReceipt(gitDir, receipt);
    assert.deepEqual(readPendingReceipt(gitDir), receipt);
    clearPendingReceipt(gitDir);
    assert.equal(readPendingReceipt(gitDir), null);
});

test("reference transactions reject a final commit whose parent differs from the audited HEAD", (t) => {
    const repository = fs.mkdtempSync(path.join(os.tmpdir(), "commit-auditor-reference-"));
    t.after(() => fs.rmSync(repository, { recursive: true, force: true }));
    const emptyHooks = path.join(repository, "empty-hooks");
    fs.mkdirSync(emptyHooks);
    runGit(repository, ["init", "-q"]);
    runGit(repository, ["config", "core.hooksPath", emptyHooks]);
    runGit(repository, ["config", "user.name", "Commit Auditor Test"]);
    runGit(repository, ["config", "user.email", "commit-auditor@example.invalid"]);
    fs.writeFileSync(path.join(repository, "base.txt"), "base\n");
    runGit(repository, ["add", "base.txt"]);
    runGit(repository, ["commit", "-qm", "[TEST] Base"]);
    fs.writeFileSync(path.join(repository, "prior.txt"), "prior\n");
    runGit(repository, ["add", "prior.txt"]);
    runGit(repository, ["commit", "-qm", "[TEST] Prior"]);

    const baseCommit = runGit(repository, ["rev-parse", "HEAD"]);
    const parentCommit = runGit(repository, ["rev-parse", "HEAD^"]);
    const headRef = runGit(repository, ["symbolic-ref", "-q", "HEAD"]);
    fs.writeFileSync(path.join(repository, "candidate.txt"), "candidate\n");
    runGit(repository, ["add", "candidate.txt"]);
    const indexTree = runGit(repository, ["write-tree"]);
    const normalCommit = runGit(repository, [
        "commit-tree",
        indexTree,
        "-p",
        baseCommit,
        "-m",
        "[TEST] Normal candidate",
    ]);
    const gitDir = runGit(repository, ["rev-parse", "--absolute-git-dir"]);
    const receipt = {
        schemaVersion: 2,
        gateId: "git-commit",
        invocationId: "generation-4.invocation-1",
        finalizationToken: "one-time-token",
        generationId: "generation-4",
        originThreadId: "thread-origin",
        auditBinding: {
            schemaVersion: 1,
            baseCommit,
            headRef,
            indexTree,
        },
    };
    writePendingReceipt(gitDir, receipt);
    runGit(repository, ["config", "core.hooksPath", __dirname]);
    execFileSync("git", ["update-ref", headRef, normalCommit, baseCommit], {
        cwd: repository,
        encoding: "utf8",
        env: { ...process.env, ...managedEnvironment },
        stdio: ["ignore", "pipe", "pipe"],
    });
    assert.equal(runGit(repository, ["rev-parse", "HEAD"]), normalCommit);
    clearPendingReceipt(gitDir);

    const amendedCommit = runGit(repository, [
        "commit-tree",
        indexTree,
        "-p",
        parentCommit,
        "-m",
        "[TEST] Replacement candidate",
    ]);
    writePendingReceipt(gitDir, {
        ...receipt,
        auditBinding: {
            ...receipt.auditBinding,
            baseCommit: normalCommit,
        },
    });
    assert.throws(
        () => execFileSync("git", ["update-ref", headRef, amendedCommit, normalCommit], {
            cwd: repository,
            encoding: "utf8",
            env: { ...process.env, ...managedEnvironment },
            stdio: ["ignore", "pipe", "pipe"],
        }),
        /amend and replacement commits are unavailable/u,
    );
    assert.equal(runGit(repository, ["rev-parse", "HEAD"]), normalCommit);
    assert.equal(readPendingReceipt(gitDir), null);
});
