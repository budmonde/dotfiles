# Global Agent Guidelines

## Coding Guidelines

### Comments

Only include comments when they provide necessary context or explanation that isn't already obvious from the code itself.
If the code is human-readable and self-explanatory, omit the comment.
Prefer clear, descriptive names over comments that restate what the code does.

### Markdown Authoring

Whenever a markdown file is being authored or edited — including `AGENTS.md`, files inside `AGENTS/`, README files, design docs, research artifacts, tickets, and any other `.md` content — load the `markdown` skill first and follow its formatting conventions. This applies to both new files and edits to existing ones.

## Project Memory Protocol

### Overview

Every project benefits from persistent long-term memory that survives context compaction and session boundaries. This protocol defines a standard `AGENTS/` directory structure for maintaining that memory.

**Memory substrates:**
- **Short-term memory** is the LLM context window — it expires after compaction.
- **Long-term memory on disk** lives in `AGENTS.md` and the `AGENTS/` directory, persisted across sessions.
- **Long-term memory in git** is the commit history of those files. Foundational documents (`mission.md`, `architecture.md`, `roadmap.md`) do **not** carry their own changelog sections; their provenance is the git log, surfaced via `git blame` and `git log -p`. Completed `todo.md` items are deleted, not checked off, because git history is the record of what was done.

**When to apply this protocol:**
- A session involves multi-step work, returns after compaction, or the project scope warrants persistent memory.
- An existing project already has `AGENTS.md` or an `AGENTS/` directory.

**When NOT to apply this protocol:**
- Trivial one-off tasks: quick bug fixes, single-file edits, ad-hoc Q&A.
- Throwaway scripts or exploratory scratch repos.

**Bootstrapping a new project**: when this protocol applies but no `AGENTS/` docs exist yet, prompt the user:

> "This project doesn't have AGENTS/ docs yet. Should I create them?"

If agreed:
1. Ask about the project's scope, architecture, and current state.
2. Propose initial content for each core file.
3. Draft the documents with user input and get approval before writing.

**Minimal valid project**: `AGENTS.md` plus `AGENTS/todo.md` is the floor. The other core files (`mission.md`, `architecture.md`, `roadmap.md`, `workflow.md`) are added as the project's scope justifies them — a small repo may never need `mission.md`. The artifact directories (`design/`, `research/`, `tickets/`) are created lazily when their first artifact appears.

**Legacy projects**: when an existing `AGENTS/` directory uses an older convention (uppercase filenames, `issues/` instead of `tickets/`, design files without `DOC<NNN>` prefixes, etc.), run the `/migrate-agents` command rather than reinventing the migration steps inline.

### Directory Taxonomy

`AGENTS.md` sits at the project root.
The `AGENTS/` directory sits alongside it.

All filenames inside `AGENTS/` are **lowercase** (`mission.md`, `architecture.md`, `workflow.md`, `todo.md`, `roadmap.md`, design docs, ticket files).
The `AGENTS/` directory name itself is uppercase as the namespace marker, and the root entry point `AGENTS.md` is uppercase by community convention (parallel to `README.md`, `LICENSE`).
This keeps prose readable — content filenames don't shout.

#### Core Files

| File | Purpose |
|------|---------|
| `AGENTS.md` | Lightweight index. Always loaded into context. See [AGENTS.md conventions](#agentsmd) for structure. |
| `AGENTS/mission.md` | Project identity, principles, goals, non-goals, scope boundaries. Answers "what is this project and what isn't it." Treated as a legal-document-like substrate: general, stable, slow-changing. |
| `AGENTS/architecture.md` | How the system works today: components, data flow, API surface, directory layout, design decisions. Present-tense — describes the system as it is *now*. |
| `AGENTS/roadmap.md` | Future plans, aspirational goals, use-case-driven direction. Also home to the **tracked deviations** list: places where current architecture or behavior deviates from mission principles, kept visible until addressed. Distinct from `todo.md` (actionable now) — `roadmap.md` is directional and longer-term. |
| `AGENTS/workflow.md` | How to operate: environment setup, build, test, deploy, project-specific conventions, audit MO. The single source for "how do I do X in this project." |
| `AGENTS/todo.md` | Active task list. Completed items are flushed entirely. Git history is the record of what was done. |

#### Artifact Directories

| Location | Purpose |
|----------|---------|
| `AGENTS/design/` | Active design documents: stubs, drafts, in-progress specs. Propose direction, define what to build, capture decisions. |
| `AGENTS/research/` | Research artifacts: chronicles, syntheses, investigation WALs. Capture what was *found* (vs. design which captures what is *decided*). Cited by design docs and foundational docs. |
| `AGENTS/tickets/` | Inbound tickets filed by other projects. Created lazily; absent if no tickets are open. The directory name matches the `TKT<NNN>` handle. |
| `AGENTS/archive/` | Sealed design docs, completed research, and resolved tickets. A chronological **write-ahead log** of past decisions, ordered by archival date — not a graveyard. Created lazily when the first artifact is archived. |

### Naming Convention

The naming scheme separates two concerns: **stable identity** (a permanent handle for cross-references) and **chronological ordering** (a useful `ls` view of the archive).

**Handles** — design docs use `DOC<NNN>`, research artifacts use `RES<NNN>`, tickets use `TKT<NNN>`. The three-letter prefix is deliberately grep-distinctive (e.g. `DOC042` has near-zero collision risk in source text). Numbers are zero-padded to at least three digits; if a project crosses 999 it does a one-time pad-to-four migration. **Each prefix has its own independent counter** — `DOC`, `RES`, and `TKT` numbering advance independently, so `DOC042`, `RES017`, and `TKT008` can coexist. Once issued, a number is permanent and never reused, PR-style.

**Active filenames**:
- `AGENTS/design/DOC<NNN>_<title>.md` (e.g. `AGENTS/design/DOC042_lazy_cache_invalidation.md`)
- `AGENTS/research/RES<NNN>_<title>.md` (e.g. `AGENTS/research/RES017_cache_eviction_chronicle.md`)
- `AGENTS/tickets/TKT<NNN>_<title>.md` (e.g. `AGENTS/tickets/TKT008_typo_in_install_script.md`)

**Archived filenames**:
`AGENTS/archive/YYYY-MM-DD_<handle>_<title>.md` (e.g. `AGENTS/archive/2026-04-08_DOC006_unmanaged_userspace_configs.md`)

The date prefix is the **archival date** — the day the artifact moves to `archive/`, not the completion date or last-active date. This is the WAL discipline: `archive/` is a chronological log of *when each artifact left the active workspace*. Same-day archivals tie in `ls`; the exact ordering within a day is not significant and is left to filesystem default.

**Titles** are lowercase `snake_case`. Keep them concise but descriptive enough to make the directory listing self-documenting.

### Cross-Reference Convention

Within prose, commit messages, and any other text, reference design docs, research artifacts, and tickets by their handle: `#DOC042`, `#RES017`, `#TKT008`. The `#` prefix marks it as a handle reference; the prefix letters disambiguate the namespace.

**Glob resolution**: `*DOC042_*.md` resolves uniquely across `design/` and `archive/` (and similarly `*RES017_*.md` across `research/` and `archive/`, `*TKT008_*.md` across `tickets/` and `archive/`) because numbers are never reused within a prefix. The leading wildcard is required because archived files carry a `YYYY-MM-DD_` date prefix while active files do not, so the handle is not anchored at the start of the filename. A reader who needs the file runs `glob **/*DOC042_*.md` from the `AGENTS/` root (or `ls design/ archive/ | grep DOC042`) and finds it regardless of which directory it currently lives in.

**Handle form is the canonical form** for stable references: handle-form citations survive archival renames automatically via glob resolution, so lifecycle sections below do not re-state this. Path-form references (`AGENTS/design/DOC042_lazy_cache_invalidation.md`) are fine when a full path is more readable, but must be updated explicitly when the target is archived.

**Cross-project references**: handles are project-scoped. When referring to a ticket or design doc in another project, prefix the handle with the project name: `dotfiles#TKT008`, `streamline#DOC042`. The bare-handle form is reserved for the current project. This avoids namespace collisions across the fleet.

### Per-File Conventions

#### `AGENTS.md`

`AGENTS.md` is the entry point loaded into every context. It must stay small. Structure:

1. **Quick reference** — project name, key commands, environment notes.
2. **Structural map** — a table describing the layout of `AGENTS/`: the core files, and the *directories* (`design/`, `research/`, `tickets/`, `archive/`) with a note on how to discover their contents (`ls AGENTS/design/`, glob on handle). Do **not** enumerate every design doc, research artifact, ticket, or archive entry; that list is the directory listing itself, and inlining it duplicates information that immediately goes stale.
3. **Workflow overrides** — project-specific overrides to default behaviors (e.g., "no test suite", "use X commit convention").
4. **Marker anchors** (optional) — named references into sub-docs for targeted lookups (either `## SECTION_NAME` heading anchors or `<!-- MARKER:topic -->` comment markers), only when a project genuinely benefits from named entry points.

#### `mission.md`

`mission.md` is the principles substrate. It states what the project *is* and what it *isn't*, the values and design principles that guide decisions, and the goals and non-goals that bound scope. It is general, stable, and slow-changing. It does not describe current-state mechanism (that's `architecture.md`) or future plans (that's `roadmap.md`).

#### `architecture.md`

Describes the system as it exists now. Present-tense only.

After completing tasks that change architecture, API surface, or system state, clean this file: remove resolved issues, delete obsolete workarounds, rewrite affected sections to reflect current reality. Never use strikethrough for resolved items — delete them entirely.

A new reader of `architecture.md` should see only what is true *now*.

#### `roadmap.md`

Covers future direction and tracked deviations.

**Tracked deviations**: when current architecture or behavior diverges from a principle stated in `mission.md`, the deviation is **flagged in `roadmap.md`** rather than silently accepted. Each entry names the principle, describes the deviation, and indicates what (if anything) the project plans to do about it. Deviations remain visible until they are either resolved, or the principle itself is revised.

This is lazy-auditing discipline: divergence is acknowledged in writing, not hidden.

#### `workflow.md`

Covers everything needed to operate in the project:
- Environment setup (dependencies, tools, configuration)
- Build and run commands
- Test commands and framework
- Deploy or release procedures
- Project-specific conventions (commit style, branch strategy, etc.)
- Audit MO (how to perform an audit against `mission.md` and clear tracked deviations)

#### `todo.md`

Format:

```markdown
## <Category>

- [P0] Critical task description
- **IN PROGRESS** [P1] Task currently being worked on
- **SKIP** [P2] Task to be skipped by automated implementation
- [P2] Lower priority task (blocked by: <reference>)
```

- Priority: `[P0]` critical, `[P1]` important, `[P2]` nice-to-have.
- Prepend `**IN PROGRESS**` when a task is being worked on.
- Prepend `**SKIP**` to exclude a task from automated implementation.
- Blocked tasks note the blocker in parentheses (use `#DOC<NNN>` handles for design-doc references).
- Completed items are **removed entirely** — do not keep them, check them off, or move them to a separate file. Git history is the record of completed work.
- When relevant, include a dependency map between design docs or task groups.

Use OpenCode's `todowrite` tool to maintain TUI visibility of progress within the session. `AGENTS/todo.md` is the canonical cross-session task list; `todowrite` is the ephemeral intra-session overlay.

### Artifact Lifecycles

#### Design Documents

Design documents cover feature specs, refactor plans, and investigation notes. They all follow the same lifecycle.

**Status line**: every design doc starts with a status line:
```
Status: Stub | Draft | In-Progress | Complete (archived YYYY-MM-DD)
```

**Lifecycle**: `Stub → Draft → In-Progress → Complete → Archived`

| Stage | Location | Filename | Description |
|-------|----------|----------|-------------|
| Stub | `design/` | `DOC<NNN>_<title>.md` | Placeholder with problem statement; design not started |
| Draft | `design/` | `DOC<NNN>_<title>.md` | Design in progress; open questions exist |
| In-Progress | `design/` | `DOC<NNN>_<title>.md` | Design decided, implementation underway |
| Complete | `archive/` | `YYYY-MM-DD_DOC<NNN>_<title>.md` | Implementation done, doc sealed with archive date |

**Archival**:
- Move from `design/` to `archive/` when implementation is complete; the rename adds the `YYYY-MM-DD_` archival-date prefix per [Naming Convention](#naming-convention).
- Update the status line: `Status: Complete (archived 2026-04-08)`.
- Remaining work from a completed doc should be extracted to `todo.md` or a new design doc rather than blocking archival.
- A completed doc's open questions should all be marked `DECIDED` or `RESOLVED` before archival.
- Path-form cross-references to the doc must be updated; handle-form references resolve automatically.

**Phased features**: when a feature has multiple phases, each phase may graduate independently. Phase 1 can be archived while Phase 2+ remains as a new or continued design doc in `design/`.

**Dependency tracking**: when design docs depend on each other, document the dependency graph in `todo.md` so the execution order is visible.

#### Research Artifacts

Research artifacts (chronicles, syntheses, investigation WALs) live in `AGENTS/research/` while active.

Unlike design docs, research artifacts do not pass through `Stub → Draft → In-Progress` states and do **not** carry a status line. They are write-ahead logs: *produced* by an investigation or synthesis job and *consumed* by downstream design and foundational documents. The presence of the file in `research/` (vs. `archive/`) is itself the status. State changes are expressed by **appending a final entry**, not by mutating a header — appending preserves the WAL's append-only discipline, while editing a header would not.

**Archival**: a research artifact moves to `archive/` when the work it captures is no longer the canonical source — typically when the design doc or mission edit it informed has landed, when a successor synthesis supersedes it, or when continued appending has stopped and the chronicle is "closed." Long-lived synthesis documents that continue to be cited may stay in `research/` indefinitely; archive when they are no longer the canonical source for downstream work.

**Sealing**: before archival, append a final entry that names the seal cause — e.g. "Sealed: informed `#DOC008` which landed 2026-05-14" or "Sealed: chronicle closed; no further appends expected." This entry is the last edit the file ever receives, after which the move to `archive/` is the only remaining action.

**Supersession**: when a newer research artifact replaces an older one, the older one is sealed with a final entry pointing at its successor (e.g. "Superseded by `#RES042`") and then archived. The successor may cite the archived predecessor by handle. The supersession relationship lives in the appended prose and the citation graph, not in a status header.

**Provenance**: when an active research file cites another (an appended chronicle citing its own job spec, a synthesis citing a chronicle, etc.), use handle-form `#DOC<NNN>` / `#RES<NNN>` so the citation network survives renames.

#### Tickets

Tickets are inbound messages from one project to another: a bug, a feature request, or a coordination item that the receiving project owns.

**Format**:

```markdown
Status: Open | In-Progress | Resolved | Rejected
Filed-by: <project-name>
Date: YYYY-MM-DD

# TKT<NNN> — <Title>

<Description of the bug or feature request, with enough context for the
receiving project to understand and act on it without the filing project's scope.>

## Resolution

<Filled in by the receiving project when resolved or rejected.>
```

**Lifecycle**:
- An agent in project A creates a file in project B's `AGENTS/tickets/` directory using the next available `TKT<NNN>` handle in project B's counter.
- Project B's agent (or a human) triages the ticket, resolves or rejects it, and updates the status and resolution section.
- On resolution, the file moves to `archive/` with the archival-date prefix.

### Commit Discipline for Foundational Documents

Amendments to foundational documents — the three core principle/state docs `mission.md`, `architecture.md`, `roadmap.md`, plus any design doc that drives an amendment to one of those three — carry their provenance in the commit message rather than in a separate changelog. The commit message should:

- Explain *why* the change is being made (what surfaced the need).
- Cite the design doc, ticket, or session that drove the change by handle (e.g. `addresses #DOC008`).
- Cite the archived research or WAL artifacts that informed the decision, by path (commit messages reference frozen paths, so path-form is the right citation form here).

When bootstrapping a new project's foundational documents in a structured session (e.g. a mission-synthesis session driven by archived research), commit in dependency order: research artifacts first (so their paths are stable), then `mission.md` (the anchor commit), then downstream documents (`roadmap.md`, `workflow.md`, `architecture.md`, etc.).

### Agent Behavior

This section consolidates the operational rules — what the agent actually does with the protocol during and after a session.

**When entering a session**:
- If `AGENTS.md` exists, load it. The structural map and any marker anchors guide targeted reads of sub-docs; don't load everything.
- If `AGENTS.md` doesn't exist and the protocol applies, prompt the user to bootstrap (see [Overview](#overview)).

**After context compaction**:
- Re-read `AGENTS.md` to recover project context. Use the structural map to pull in only what the current task needs.

**After completing significant work**, verify that `AGENTS/` documentation reflects current reality:
- `architecture.md` describes the system as it is now (no stale references).
- `workflow.md` has correct commands and procedures.
- `todo.md` has no completed items lingering.
- `roadmap.md` tracked-deviations list is current.
- Design docs in `design/` have accurate status lines; completed ones are archived.
- Research artifacts that informed landed decisions are sealed and archived.
- Resolved tickets are archived.
- `AGENTS.md` structural map lists currently-present core files and directories (artifact directories may be legitimately absent — don't fabricate them).

**Periodically**, when a significant chunk of work completes, prompt the user:

> "This may have significantly changed the codebase. Would you like me to review the agent documentation for integrity?"

If agreed, audit flow/organization, accuracy, redundancy, and staleness across all `AGENTS/` files.

### Default Memory Scope

The default assumption is **one `AGENTS/` per repository**, sitting next to the repo's root `AGENTS.md`.

Projects that deviate from this default — monorepos with per-subproject scoping, multi-repo workspaces with workspace-level memory, projects that rename or relocate the index file — must declare and justify the deviation in their own index (the equivalent of `AGENTS.md`), and configure their loader (`opencode.json` or similar) to point at the relocated index. The PMP does not prescribe these deviations; it only requires that they be made explicit in the project that adopts them.

### Anti-Patterns

Common mistakes to avoid:

- **Keeping a `changelog.md` in `AGENTS/`** — git history is the changelog. Foundational-doc changes carry provenance in commit messages.
- **Strikethrough for resolved items** — delete them. `architecture.md` describes the system as it is *now*; struck-through prose is noise.
- **Checking off or moving completed todos** — delete them entirely. Git history is the record of what was done.
- **Enumerating individual design docs in `AGENTS.md`** — the index lists *directories*; agents discover contents via `ls`.
- **Reusing a retired handle** — handles are permanent once issued, PR-style, even if the artifact is deleted.
- **Path-form references in cross-project prose** — paths break when the target is archived in the other project. Use handle form (`projectname#DOC042`).
- **Uppercase content filenames** (`MISSION.md`, `TODO.md`) — content files inside `AGENTS/` are lowercase. `AGENTS/` and root `AGENTS.md` retain uppercase by convention.
- **Inventing migration steps for legacy `AGENTS/` directories** — run `/migrate-agents` instead.

<!-- opencode-marketplace:start -->
## Marketplace Skills (ocmp-* prefix)

Skills prefixed with `ocmp-` are imported from Claude Code plugin marketplaces
via opencode-marketplace. When using these skills:

- `${CLAUDE_PLUGIN_ROOT}`, `$CLAUDE_PLUGIN_ROOT`, and `{{PLUGIN_DIR}}` are path
  variables. Run `opencode-marketplace resolve <skill-name>` to get the actual
  paths for CLAUDE_PLUGIN_ROOT and CLAUDE_SKILL_DIR. The skill name is shown in
  the `<skill_content name="...">` tag when the skill is loaded.
- `${CLAUDE_SKILL_DIR}` refers to the directory containing the skill's SKILL.md.
  Also resolved by the `resolve` command.
- `!\`command\`` syntax (backtick preprocessing) means you should execute that
  command and use its output as context.
- `mcp__<server>__<tool>` references refer to MCP server tools. Match them to
  your configured MCP servers by name and function.
- `allowed-tools` in frontmatter is advisory — it indicates which tools the skill
  was designed to use, but is not enforced.
- `disable-model-invocation` and `user-invocable` are Claude Code flags preserved
  for documentation; they have no effect in OpenCode.
<!-- opencode-marketplace:end -->
