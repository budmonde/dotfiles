---
name: commit-auditor
description: Run and troubleshoot the managed Codex commit gate. Use before invoking git commit from a Codex App Server session, when a commit-msg hook reports a gate invocation, when the user asks whether an evaluator finished or why a commit was rejected, or when validating the managed commit-gate flow.
---

# Commit auditor

Treat the hook's verdict as binding.
Do not bypass the hook or commit on the user's behalf after a rejection.

## Run a managed commit

Set the shell-command timeout to at least 360000 milliseconds when invoking `git commit`.
The `commit-msg` hook waits synchronously for the evaluator,
so the normal short command timeout is insufficient.

On Windows,
if the sandbox cannot create the Git process,
retry the exact commit command with `sandbox_permissions` set to `require_escalated`
and the same extended timeout.
Do not broaden the command or approval scope.

The hook audits the staged index and binds its `HEAD` and index-tree snapshot to the proposed commit during Git's `reference-transaction` phase.
Managed amend and replacement commits are rejected because their final diff is not the staged diff that `commit-msg` audited.
Recreate the intended change as a new holistic commit instead of retrying an amend.

If a commit command times out,
do not immediately retry it.
First inspect `HEAD`,
`git status`,
and any reported gate invocation because the Git process may have completed after the caller stopped waiting.

## Query a gate invocation

Copy the `gate invocation: <id>` value printed by the hook.
From the same originating Codex thread,
run:

```powershell
codex-ctl gate status --invocation <id> --json
```

The controller reads its capability from the managed process environment.
Do not read,
print,
or pass the broker token directly.

Interpret these states:

- `starting` or `running`: the evaluator has not completed.
- `awaiting-finalization`: the verdict was `APPROVE` or `REWRITE`;
  Git has not finalized the resulting commit yet.
- `archived`: the broker finalized and archived the evaluator thread.
- `archived` with `finalization.status` `aborted`: Git rejected the final transaction because it no longer matched the audited snapshot.
- `infrastructure-failed`: App Server,
  broker,
  policy loading,
  scope validation,
  or structured output failed.

The query is constrained to the invocation ID,
origin thread ID,
and controller generation.
A mismatch is an identity error,
not evidence that the invocation is absent.

## Respond to a verdict

- `APPROVE`: let the in-flight Git command continue.
- `REWRITE`: inspect the message Git reports and explain the evaluator's rationale if needed.
- `REJECT`: address the named diff,
  scope,
  convention,
  or infrastructure problem before retrying.

If App Server or the broker is unhealthy,
run `codex-ctl gate health git-commit --json`
and `codex-ctl host status`.
The correct degraded behavior is a rejected commit with an infrastructure explanation.
Do not silently bypass auditing inside a managed session.
The user may intentionally launch an unmanaged direct Codex session as a separate fallback;
its commits follow local hook policy and must not be represented as managed audits.
