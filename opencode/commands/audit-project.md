---
description: Run a workspace-scoped audit (intra-wiki health, cross-doc self-consistency, code-vs-wiki alignment, audit-pipeline meta-state) via the wiki-auditor agent fleet, then auto-chain into the reconciler to apply findings.
---

Dispatcher for the wiki-audit workflow.
This command runs the full audit-reconciliation loop end to end:
the audit phase produces a structured findings report,
the reconciliation phase partitions the findings across parallel executors and lands them as a single `[AUDIT]` rollup commit,
and the operator-signoff phase (out of scope of this command) closes the loop.

The dispatcher is intentionally thin.
It does workspace detection,
worktree setup,
orchestrator dispatch,
report surfacing,
reconciler dispatch,
final summary,
and cleanup.
All audit and reconciliation logic lives in the `wiki-auditor/*` agent fleet.

Where the steps below show `git <verb> ...` prose,
issue it with the `bash` tool's `workdir` parameter set to the appropriate substrate
(per the global `workdir`-over-`git -C` convention in `~/.config/opencode/AGENTS.md`).

## Process

### 1. Resolve workspace root and target scope

Determine the workspace root and the documentation directory inside it.

- If a wiki index file (e.g. `wiki/index.md`) exists at the current working directory, the workspace root is the cwd and the docs directory is `wiki/`.
- Otherwise if `AGENTS.md` exists at the cwd, the workspace root is the cwd and the docs directory is `AGENTS/`.
- Otherwise walk up one parent directory and repeat.
  If neither is found within a reasonable depth, abort with an error naming the search path.

Record:

- `workspace_root` (absolute path)
- `docs_dir` (`wiki` or `AGENTS`)
- `repo_shape`:
  one of `wiki-in-own-repo` (the docs directory is its own git repository, e.g. a separately-versioned wiki sibling),
  `agents-as-subdir` (the docs directory is a subdirectory of a larger source repo, protocol-default),
  or `multi-repo-mixed` (workspace has multiple repos of mixed shape).

Detect `repo_shape` by running `git rev-parse --show-toplevel` (with `workdir: <docs_dir>`) and comparing the result to `<docs_dir>` itself
(if the toplevel equals `<docs_dir>` the docs directory is its own repo;
if the toplevel is an ancestor, the docs are a subdir of that repo).

### 2. Create worktree(s) per the project's wiki-location shape

Worktree-scope detection follows these rules:

- **wiki-in-own-repo**:
  create a single worktree of the docs repo only.
  Companion repos in the workspace are read from their live working trees
  (read-only, no mutation risk; the audit issues no `write` or `edit` against them).
- **agents-as-subdir**:
  subdirectory worktrees are not a git primitive;
  worktree the whole source repo.
- **multi-repo-mixed**:
  apply the per-repo rule above.

Worktree path convention:
`<workspace_root>/.audit-worktree/<docs_dir>-<short-head>` (e.g. `.audit-worktree/wiki-c7deb14`),
where `<short-head>` is `git rev-parse --short HEAD` of the docs repo at dispatch time.
Use `git worktree add <path> HEAD` (with `workdir: <repo>`) to create it.

Record the worktree path(s) and pass them to the orchestrator.

### 3. Dispatch the wiki-audit orchestrator with a job spec

Use the `task` tool with `subagent_type: "wiki-auditor/orchestrator"` and a prompt containing the job spec.

The job spec is structured prose with these fields:

- `workspace_root`: absolute path
- `docs_dir`: `wiki` or `AGENTS`
- `repo_shape`: one of the three values above
- `worktree_paths`: list of worktree absolute paths (with the docs worktree explicitly identified)
- `companion_repo_paths`: list of live working trees the wiki-code-alignment-checker should read against
  (one absolute path per companion repo in the workspace)
- `report_destination`: a file path under the worktree where the orchestrator may persist intermediate state if needed
  (the final report is returned in the orchestrator's reply, not via this file)
- `path_map`: a structured block (see below) that the orchestrator forwards verbatim to every downstream worker and the critic.
  The dispatcher is the only component that knows which substrates were worktree'd vs. read live;
  emitting the canonical map here keeps every downstream child indifferent to the live-workspace shape.

#### `path_map` shape

The `path_map` is a YAML-shaped block with three top-level keys:

```yaml
worktree_substrates:
  <substrate-name>: <absolute-worktree-path>
live_substrates:
  <substrate-name>: <absolute-live-path>
docs_root_in_worktree: <absolute-worktree-path>
```

Rules for populating it:

- `worktree_substrates` lists every substrate that received a worktree in step 3.
  For `wiki-in-own-repo` shape, this is the docs substrate alone (e.g. `<docs-substrate-name>: <worktree-path>`).
  For `agents-as-subdir` shape, this is the source repo as a whole.
- `live_substrates` lists every companion repo the auditor reads from its live working tree (read-only).
  Each entry maps a substrate name (chosen by the dispatcher to match how the wiki refers to that repo) to its absolute live path.
- `docs_root_in_worktree` is the canonical anchor for foundational-doc reads.
  In `wiki-in-own-repo` shape this is the same path as the docs substrate's worktree entry,
  because the docs sit at the worktree root with no docs-directory prefix.
  In `agents-as-subdir` shape this is `<worktree>/AGENTS/`,
  because the docs sit under the `AGENTS/` subdirectory of the worktreed source repo.

Downstream agents read paths only from this map.
They do not reconstruct paths from the live workspace shape;
that shape is the dispatcher's concern and is invisible to workers.
This contract is invariant under future sandboxing:
the dispatcher emits sandbox-mount paths in the map, and worker prose stays unchanged.

Wait for the orchestrator to return the final structured report.

### 4. Render the structured report to the operator

Surface the report as the body of the response.
Do not summarize or paraphrase;
the orchestrator's output is the operator-visible artifact.

The expected report structure:

- **Scope statement**:
  workspace root, docs dir, worktree paths.
- **Artifact findings** table:
  `| Worker | Category | Finding | Evidence | Severity | Attribution | Root cause | Proposed action |`
  where Attribution is `recent` / `chronic` / `unknown`.
- **Recommended runbook amendments** section
  (the runbook-flaw findings, each pointing at the specific section of `workflow.md`, the global PMP, an agent definition, or a skill that needs amendment).
- **Pre-archival proposals** section
  (artifacts the health-checker proposed for archival, with readiness verdict).
- **Critic disposition** section
  (which critic verdicts were accepted, defended, or downgraded by the orchestrator).
- **Tool-denial soft-fail log**
  (worker-reported tool denials and the fallback methods used).

### 5. Dispatch the reconciler against the report

Use the `task` tool with `subagent_type: "wiki-auditor/reconciler"` and a prompt containing the reconciler job spec.

The reconciler is the agent that drives the reconciliation phase end to end.
It partitions the findings by target substrate, fans out one `wiki-auditor/executor` per partition (in parallel), composes the rollup commit message from their returned summaries, then dispatches `wiki-auditor/audit-committer` to produce the single `[AUDIT]` commit.
The dispatcher does not see these substeps directly;
it sees only the reconciler's final structured summary.

The reconciler job spec contains:

- `worktree_path`:
  the docs worktree path created in step 2.
- `companion_repo_paths`:
  the same companion repo paths surfaced to the orchestrator
  (read-only references that executors may need for empirical questions).
- `audit_pass_date`:
  the calendar date of this audit pass (used in the rollup commit subject, scratch document name, and ticket `Date:` fields).
- `findings_report`:
  the orchestrator's structured report, transcribed verbatim from step 4.
- `ticket_counter_start`:
  the next available `TKT<NNN>` number in the workspace's ticket counter.
  Determine this by `ls <docs_root>/tickets/ <docs_root>/archive/ | grep -oE 'TKT[0-9]+'` (or platform equivalent), parsing the highest existing handle and adding 1.

The reconciler returns a structured summary naming the rollup commit hash, the partition layout, the applied-finding handles per partition, the filed-ticket handles, any already-applied findings, any cross-partition deferrals, and the `commit-auditor` verdict on the rollup commit (APPROVE / REWRITTEN / REJECTED).

### 6. Surface the reconciler result

Render the reconciler's summary to the operator immediately after the audit report.
Do not paraphrase;
the reconciler's output is the operator-visible artifact for the reconciliation phase.

If the reconciler reports the audit verdict as `REWRITTEN`, surface that prominently.
A rewrite means the `commit-auditor` swapped the `[AUDIT]` tag for a substrate tag,
which indicates either a regression in the tag-reservation infrastructure or a legitimate scope violation in the staged set.
The operator must investigate before the next audit pass.

If the reconciler reports filed tickets,
the audit-reconciliation loop is not yet closed.
The operator must triage each ticket per the project's ticket-discipline section (typically `<docs_root>/workflow.md#ticket-discipline`)
(operator fills in `## Resolution`, then a follow-up agent applies and archives).
Surface this expectation explicitly:

> "The reconciliation phase filed `<M>` operator-signoff tickets that need your review before the audit loop closes.
> See `<docs_root>/tickets/TKT<NNN>_*.md` for each."

If the reconciler reports no filed tickets,
the audit-reconciliation loop is closed by the rollup commit alone.

### 7. Offer worktree cleanup

After the report is surfaced, ask the operator:

> "The audit worktree(s) at `<paths>` are still on disk.
> Remove them now? (y/N)"

If the operator confirms,
run `git worktree remove <path>` (with `workdir: <repo>`) for each worktree created in step 2.
Otherwise leave them in place
(the operator may want to keep them open for a follow-up reconciliation phase or to inspect the audited state directly).

## Constraints

- The audit phase (steps 1-4) is read-only by output.
  The orchestrator and its worker fleet have no `write` or `edit` permissions
  (enforced in their agent frontmatter).
- The reconciliation phase (steps 5-6) is the reconciler's responsibility.
  The reconciler writes only inside the docs worktree's `.audit-scratch/` directory;
  the executors it dispatches write the actual edits inside the docs worktree;
  the audit-committer it dispatches produces exactly one `[AUDIT]` rollup commit;
  none of them push, merge, or modify branches.
  See the `wiki-auditor/reconciler`, `wiki-auditor/executor`, and `wiki-auditor/audit-committer` agent definitions for the full reconciliation-phase discipline.
- The `[AUDIT]` commit tag is reserved for the `wiki-auditor/audit-committer` agent.
  The `commit-auditor` enforces this reservation by reading `OPENCODE_SESSION_AGENT` from the calling session;
  any other dispatching agent (including the reconciler and the executors that prepared the staged set) that proposes `[AUDIT]` is rewritten to a substrate tag.
  The reservation lives on the audit-committer rather than on the agent that performed the edits because the audit-committer's session is deliberately short (one tool call) and therefore not vulnerable to the compaction race that overwrites `OPENCODE_SESSION_AGENT` mid-session.
  Workers in the audit phase that need an audit-window scope look up the most recent `[AUDIT]` commit locally
  (`git log --grep='^\[AUDIT\]' -1` with `workdir: <docs_root>`);
  the dispatcher does not thread a high-water mark through the job spec.
- Operator-signoff tickets filed during reconciliation close the audit loop only after the operator records a resolution.
  This dispatcher is *not* responsible for waiting on or applying ticket resolutions;
  that is a separate operator-driven follow-up phase.
- If the workspace cannot be detected,
  abort with a clear error;
  do not attempt a partial audit against an unidentified root.

## Cron / unattended use

When a calendar/cron substrate lands,
this same command becomes one of several entry points to the same underlying job spec.
The dispatcher and the cron caller produce the same job spec;
the orchestrator does not know or care which dispatched it.
The job-spec shape above is the wire format both entry points populate.
A future sandboxing variant runs the audit in an isolated environment; the job-spec shape is unchanged.
