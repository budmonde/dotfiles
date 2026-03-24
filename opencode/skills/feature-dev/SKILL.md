---
name: feature-dev
description: Structured workflow for developing medium-to-large features with documentation-first, test-driven development
---

## What This Skill Does

This skill provides a structured development workflow for implementing medium-to-large features. It ensures code changes are accompanied by documentation updates and tests, keeping the codebase maintainable and the project state always visible in documentation.

## When to Use

Use this skill when:
- Implementing a new feature that touches multiple files
- Making significant changes to existing functionality
- Working on tasks from a roadmap or backlog

Do NOT use for:
- Quick bug fixes (single file, obvious fix)
- Minor refactors or cleanup
- Exploratory/spike work

## Key Principles

1. **Documentation-first**: The plan exists in documentation before code exists
2. **Test-driven**: Tests define expected behavior before implementation
3. **Atomic changes**: Each loop produces one committable unit of work
4. **Single source of truth**: Project state is always visible in documentation
5. **Lean context**: Keep frequently-accessed files small; archive completed work
6. **STATE.md is present-tense**: STATE.md describes the system as it is *now*, not its history — remove resolved issues, don't strike them through

## Documentation Structure

This workflow uses a standard `AGENTS.md` file plus an `AGENTS/` directory:

| File | Purpose |
|------|---------|
| `AGENTS.md` | Short index with quick reference, markers for lookups into AGENTS/STATE.md, project-specific workflow overrides |
| `AGENTS/STATE.md` | Full documentation: architecture, API reference, system state, design decisions |
| `AGENTS/TODO.md` | Canonical task list — pending and in-progress items only |
| `AGENTS/DONE.md` | Completed tasks — periodically flushed with user instruction |
| `AGENTS/SCRATCH_<slug>.md` | Temporary working notes scoped to a task — implementation plans, intermediate state, decisions in progress. Deleted after use |

**Why this structure?**
- `AGENTS.md` stays small for fast context loading
- `AGENTS/STATE.md` holds comprehensive docs loaded only when needed
- Separating TODO/DONE keeps task lists lean and prevents completed work from cluttering active planning
- `AGENTS/SCRATCH_<slug>.md` provides a persistent scratchpad that survives context compaction, unlike in-session state. Each session picks a unique slug, allowing parallel agents to work without collisions
- Avoids conflicts with project README.md files

### TODO.md Format

```
## <Category>

- [P0] Critical task description
- **IN PROGRESS** [P1] Task currently being worked on
- **SKIP** [P2] Task to be skipped by automated implementation
- [P2] Lower priority task (blocked by: <reference>)
```

- Priority: `[P0]` critical, `[P1]` important, `[P2]` nice-to-have
- Prepend `**IN PROGRESS**` when a task is being worked on
- Prepend `**SKIP**` to exclude a task from automated implementation (e.g. `/implement`)
- No checkboxes or done markers — completed tasks are removed and moved to DONE.md
- Blocked tasks note the blocker in parentheses

## Before Starting

### Check for Existing Documentation

1. Does the current directory or target subproject already have an `AGENTS.md`?
2. Is there a root-level `AGENTS.md` that covers the whole repo?
3. For monorepos: which scope is appropriate — root or subproject?

If unclear, ask: *"Should I use the root-level agent docs, or create/use subproject-specific docs in `<subproject>/`?"*

### Check for Project-Specific Overrides

The project's `AGENTS.md` may contain workflow overrides (e.g., `## Workflow Overrides` section). These take precedence over this skill's defaults. Examples:
- Different test commands or frameworks
- Specific commit message conventions
- Additional documentation files to update
- Modified loop steps (e.g., skip tests for certain change types)

### Create Documentation if Missing

If no agent documentation exists, consult with the user to create it. Call `todowrite` to track the setup steps:
1. Ask about the project's scope, architecture, and current state
2. Propose initial content for each file:
   - `AGENTS.md`: Project name, quick reference, environment setup, markers index
   - `AGENTS/STATE.md`: Architecture overview, directory structure, API docs, design decisions
   - `AGENTS/TODO.md`: Initial task list based on user's goals
   - `AGENTS/DONE.md`: Header explaining its purpose (starts empty)
3. Draft the documents with user input and get approval before proceeding

## The Development Loop

Use OpenCode's `todowrite` tool to maintain TUI visibility of progress within each loop iteration. `AGENTS/TODO.md` remains the canonical cross-session task list — `todowrite` is the ephemeral intra-session overlay for tracking sub-steps. Use `todoread` to recover the current state after context compaction. If `todowrite` is unavailable (e.g., running as a subagent), proceed without it.

For non-trivial tasks, use `AGENTS/SCRATCH_<slug>.md` as a working scratchpad to record implementation plans, intermediate state, open questions, and decisions in progress. Before creating the file, list `AGENTS/` to check for existing `SCRATCH_*.md` files and choose a descriptive kebab-case `<slug>` that doesn't collide (e.g., `SCRATCH_add-auth-middleware.md` — if that exists, be more specific like `SCRATCH_add-auth-settings-route.md`). Unlike `todowrite` state, this file persists across context compactions and session restarts. Write to it freely during the loop, but always delete it before committing (step 6). Never delete another session's scratch file.

Follow this loop for every task.

### 1. Pick the Task

Read `AGENTS/TODO.md`. Identify the highest-priority item that is not blocked. Prefer items that unblock other work.

Call `todowrite` to register the loop steps for this task (Plan, Write Tests, Implement, Update Docs, Commit). Mark each step `in_progress` when entering it and `completed` when done throughout the loop.

### 2. Plan in Documentation

Before writing any code:
- Prepend **IN PROGRESS** to the item in `AGENTS/TODO.md`
- For non-trivial tasks, write the plan in `AGENTS/SCRATCH_<slug>.md`: what files change, expected behavior, migration concerns

### 3. Write Tests First

- Write the test that exercises the new/changed behavior *before* implementing
- For bug fixes, write a test that reproduces the bug and verify it fails
- Run the full test suite — only your new test should fail

If the project has no test suite, write tests as you go, building coverage incrementally. Discuss with the user what testing framework fits the project.

### 4. Implement

- Make the code change, keeping it minimal and focused
- Run the test suite — all tests must pass
- Update build configuration if adding new files

### 5. Update Documentation

- Remove the completed task from `AGENTS/TODO.md` and add it to `AGENTS/DONE.md`
- **Clean `AGENTS/STATE.md`**: Remove any content that the completed task made obsolete — bugs, limitations, workarounds, known issues, or temporary states that no longer apply. Do NOT use strikethrough to mark resolved items; delete them entirely and rewrite the surrounding section to describe the current state. STATE.md must always read as a clean, present-tense description of the system, never as a changelog.
- Update `AGENTS/STATE.md` if APIs, architecture, or system state changed
- Update `AGENTS.md` index if new markers or sections were added
- Add any newly discovered issues to `AGENTS/TODO.md` and call `todowrite` to add them as `pending` items for session visibility

### 6. Commit and Repeat

Delete `AGENTS/SCRATCH_<slug>.md` if it exists — scratch notes must not be committed. Create an atomic commit, then return to step 1.

## Housekeeping

**Flushing AGENTS/DONE.md**: When the user instructs, summarize and clear completed tasks. Optionally move summaries to a changelog. This keeps documentation lean.

**STATE.md Hygiene**: `AGENTS/STATE.md` must always read as a clean, present-tense snapshot of the system. After completing tasks, verify that STATE.md contains no:
- ~~Struck-through~~ items describing resolved issues
- "Known issues" or "limitations" sections listing problems that have been fixed
- Workaround descriptions for bugs that no longer exist
- Transitional language ("currently broken", "will be fixed") for things that are already resolved

If any of these are found, rewrite the affected sections to reflect current reality and delete content that no longer applies. The goal: a new reader of STATE.md should see only what is true *now*.

**Documentation Integrity Review**: After completing a significant chunk of work (e.g., a major feature, multiple related tasks, or work that substantially changed the codebase architecture), prompt the user:

*"I've completed [describe work]. This may have significantly changed the codebase. Would you like me to review the agent documentation (AGENTS.md and AGENTS/*.md) for integrity?"*

If the user agrees, call `todowrite` to track the review sub-steps, then read through all agent documentation files and check:
- **Flow and organization**: Do sections appear in logical order? Are related concepts grouped?
- **Accuracy**: Does the documentation reflect the current state of the codebase?
- **Redundancy**: Are concepts repeated across files? Can sections be consolidated?
- **Staleness**: Are there references to removed/renamed components?

Suggest refactors or rewrites as needed. This prevents documentation from drifting out of sync with the codebase over time.
