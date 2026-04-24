# Global Agent Guidelines

## Coding Guidelines

### Comments

Only include comments when they provide necessary context or explanation that isn't already obvious from the code itself.
If the code is human-readable and self-explanatory, omit the comment.
Prefer clear, descriptive names over comments that restate what the code does.

## Project Memory Protocol

Every project benefits from persistent long-term memory that survives context compaction and session boundaries.
This protocol defines a standard `AGENTS/` directory structure for maintaining that memory.

**Short-term memory** is the LLM context window — it expires after compaction.
**Long-term memory** lives in `AGENTS.md` and the `AGENTS/` directory, persisted to disk and reloaded across sessions.

### When to Create AGENTS/ Documentation

When a session involves multi-step work, returns after compaction, or the project scope warrants persistent memory, prompt the user:

> "This project doesn't have AGENTS/ docs yet. Should I create them?"

Do NOT prompt for trivial one-off tasks (quick bug fixes, single-file edits, Q&A).

When creating documentation for a new project:
1. Ask about the project's scope, architecture, and current state
2. Propose initial content for each core file
3. Draft the documents with user input and get approval before writing

### Directory Taxonomy

`AGENTS.md` sits at the project root.
The `AGENTS/` directory sits alongside it.

#### Core Files (present in most projects)

| File | Purpose |
|------|---------|
| `AGENTS.md` | Lightweight index. Always loaded into context. Contains quick reference (key commands, env), documentation index table, and marker anchors into sub-docs. Keep this small. |
| `AGENTS/ARCHITECTURE.md` | How the system works: components, data flow, API surface, directory layout, design decisions. Present-tense — describes the system as it is *now*. |
| `AGENTS/WORKFLOW.md` | How to operate: environment setup, build, test, deploy, project-specific conventions, workflow overrides. The single source for "how do I do X in this project." |
| `AGENTS/TODO.md` | Active task list. Completed items are flushed (removed entirely). Git history is the record of what was done. |

#### Optional Files (use when the project needs them)

| File | Purpose | When to use |
|------|---------|-------------|
| `AGENTS/MISSION.md` | Project identity: values, design principles, goals, non-goals, scope boundaries. Answers "what is this project and what isn't it." | Projects where scope drift is a concern, or where design principles need to be explicit to prevent feature creep. |
| `AGENTS/ROADMAP.md` | Future plans, aspirational goals, use-case-driven direction. Distinct from TODO (actionable now) vs ROADMAP (directional, longer-term). | Projects with a vision beyond immediate tasks. |

#### Design Documents

| Location | Purpose |
|----------|---------|
| `AGENTS/design/` | Active design documents: stubs, drafts, in-progress specs, analyses, research. |
| `AGENTS/archive/` | Completed design documents, sealed with decision logs and archive dates. |

#### Cross-Project Issues

| Location | Purpose |
|----------|---------|
| `AGENTS/issues/` | Incoming issues filed by other projects (bug reports, feature requests). Each issue is a markdown file. |

Issues are filed by agents working in other project scopes that discover bugs or need features from this project.
Each issue is a markdown file with a status line and enough context for the receiving project to act on it independently.

**Issue format:**
```markdown
Status: Open | In-Progress | Resolved | Rejected
Filed-by: <project-name>
Date: YYYY-MM-DD

## <Title>

<Description of the bug or feature request, with enough context for the
receiving project to understand and act on it without the filing project's scope.>

## Resolution

<Filled in by the receiving project when resolved or rejected.>
```

**Lifecycle:**
- An agent in project A creates a file in project B's `AGENTS/issues/` directory
- Project B's agent (or a human) triages the issue, resolves or rejects it, and updates the status and resolution section
- Resolved/rejected issues are flushed periodically, same as TODO items

### AGENTS.md Index Conventions

`AGENTS.md` is the entry point loaded into every context.
It must stay small.
Structure:

1. **Quick reference** — project name, key commands, environment notes
2. **Documentation index** — table listing every `AGENTS/` file with a one-line description
3. **Marker anchors** — named references into sub-docs for targeted lookups (either `## SECTION_NAME` heading anchors or `<!-- MARKER:topic -->` comment markers)
4. **Workflow overrides** — project-specific overrides to default behaviors (e.g., "no test suite", "use X commit convention")

### ARCHITECTURE.md Conventions

Describes the system as it exists now.
Present-tense only.

After completing tasks that change architecture, API surface, or system state, clean this file: remove resolved issues, delete obsolete workarounds, rewrite affected sections to reflect current reality.
Never use strikethrough for resolved items — delete them entirely.

A new reader of ARCHITECTURE.md should see only what is true *now*.

### WORKFLOW.md Conventions

Covers everything needed to operate in the project:
- Environment setup (dependencies, tools, configuration)
- Build and run commands
- Test commands and framework
- Deploy or release procedures
- Project-specific conventions (commit style, branch strategy, etc.)

### TODO.md Format

```markdown
## <Category>

- [P0] Critical task description
- **IN PROGRESS** [P1] Task currently being worked on
- **SKIP** [P2] Task to be skipped by automated implementation
- [P2] Lower priority task (blocked by: <reference>)
```

- Priority: `[P0]` critical, `[P1]` important, `[P2]` nice-to-have
- Prepend `**IN PROGRESS**` when a task is being worked on
- Prepend `**SKIP**` to exclude a task from automated implementation
- Blocked tasks note the blocker in parentheses
- Completed items are **removed entirely** — do not keep them, check them off, or move them to a separate file.
  Git history is the record of completed work.
- When relevant, include a dependency map between design docs or task groups

Use OpenCode's `todowrite` tool to maintain TUI visibility of progress within the session.
`AGENTS/TODO.md` is the canonical cross-session task list; `todowrite` is the ephemeral intra-session overlay.

### Design Document Lifecycle

Design documents cover feature specs, refactor plans, research/analysis, and investigation notes.
They all follow the same lifecycle and conventions.

**Naming convention:** `NNN_SNAKE_CASE_TITLE.md`
- `NNN` is a zero-padded sequential number assigned at creation (e.g., `001`, `042`, `137`)
- The number is permanent — it does not change when moving between directories
- Numbers span both `design/` and `archive/` (no renumbering on archival)

**Status line:** Every design doc starts with a status line:
```
Status: Stub | Draft | In-Progress | Complete (archived YYYY-MM-DD)
```

**Lifecycle:**

```
stub → draft → in-progress → complete → archived
```

| Stage | Location | Description |
|-------|----------|-------------|
| Stub | `design/` | Placeholder with problem statement; design not started |
| Draft | `design/` | Design in progress; open questions exist |
| In-Progress | `design/` | Design decided, implementation underway |
| Complete | `archive/` | Implementation done, doc sealed with archive date |

**Archival rules:**
- Move from `design/` to `archive/` when implementation is complete
- Add archive date to status line: `Status: Complete (archived 2026-04-08)`
- Remaining work from a completed doc should be extracted to TODO.md or a new design doc rather than blocking archival
- A completed doc's open questions should all be marked `DECIDED` or `RESOLVED`

**Phased features:** When a feature has multiple phases, each phase may graduate independently.
Phase 1 can be archived while Phase 2+ remains as a new or continued design doc in `design/`.

**Dependency tracking:** When design docs depend on each other, document the dependency graph in `TODO.md` so the execution order is visible.

### Maintaining Long-Term Memory

**After completing significant work**, verify that AGENTS/ documentation reflects current reality:
- ARCHITECTURE.md describes the system as it is now (no stale references)
- WORKFLOW.md has correct commands and procedures
- TODO.md has no completed items lingering
- Design docs in `design/` have accurate status lines
- AGENTS.md index lists all current files

**After context compaction**, re-read AGENTS.md to recover project context.
The index and markers allow targeted reads of sub-docs as needed rather than loading everything.

**Periodically**, when a significant chunk of work completes, prompt the user:

> "This may have significantly changed the codebase. Would you like me to review the agent documentation for integrity?"

If agreed, check flow/organization, accuracy, redundancy, and staleness across all AGENTS/ files.

<!-- opencode-marketplace:start -->
## Marketplace Skills (ocmp-* prefix)

Skills prefixed with `ocmp-` are imported from Claude Code plugin marketplaces via opencode-marketplace.
When using these skills:

- `${CLAUDE_PLUGIN_ROOT}`, `$CLAUDE_PLUGIN_ROOT`, and `{{PLUGIN_DIR}}` are path variables.
  Run `opencode-marketplace resolve <skill-name>` to get the actual paths for CLAUDE_PLUGIN_ROOT and CLAUDE_SKILL_DIR.
  The skill name is shown in the `<skill_content name="...">` tag when the skill is loaded.
- `${CLAUDE_SKILL_DIR}` refers to the directory containing the skill's SKILL.md.
  Also resolved by the `resolve` command.
- `!\`command\`` syntax (backtick preprocessing) means you should execute that command and use its output as context.
- `mcp__<server>__<tool>` references refer to MCP server tools.
  Match them to your configured MCP servers by name and function.
- `allowed-tools` in frontmatter is advisory — it indicates which tools the skill was designed to use, but is not enforced.
- `disable-model-invocation` and `user-invocable` are Claude Code flags preserved for documentation; they have no effect in OpenCode.
<!-- opencode-marketplace:end -->
