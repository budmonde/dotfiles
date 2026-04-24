---
name: feature-dev
description: Structured workflow for developing medium-to-large features with documentation-first, test-driven development
---

## What This Skill Does

This skill provides a structured development loop for implementing features.
It ensures code changes are accompanied by tests, documentation stays current, and each commit is an atomic unit of work.

The AGENTS/ directory structure, design document lifecycle, and long-term memory conventions are defined in the **global Project Memory Protocol** (in the global `AGENTS.md`).
This skill focuses solely on the development workflow that operates within that system.

## When to Use

Use this skill when:
- Implementing a new feature that touches multiple files
- Making significant changes to existing functionality
- Working on tasks from a TODO or roadmap

Do NOT use for:
- Quick bug fixes (single file, obvious fix)
- Minor refactors or cleanup
- Exploratory/spike work

## Key Principles

1. **Documentation-first**: The plan exists in documentation before code exists
2. **Test-driven**: Tests define expected behavior before implementation
3. **Atomic changes**: Each loop produces one committable unit of work
4. **Single source of truth**: Project state is always visible in AGENTS/ documentation

## Before Starting

### Check for Project Documentation

1. Does the project have an `AGENTS.md` and `AGENTS/` directory?
2. If not, follow the global Project Memory Protocol to create them — ask the user first.
3. For monorepos: which scope is appropriate — root or subproject?

### Check for Workflow Overrides

The project's `AGENTS.md` or `AGENTS/WORKFLOW.md` may contain workflow overrides.
These take precedence over this skill's defaults.
Examples:
- Different test commands or frameworks
- Specific commit message conventions
- Modified loop steps (e.g., skip tests for certain change types)
- "No test suite" declaration

## The Development Loop

Use OpenCode's `todowrite` tool to maintain TUI visibility of progress within each loop iteration.
`AGENTS/TODO.md` remains the canonical cross-session task list — `todowrite` is the ephemeral intra-session overlay.
If `todowrite` is unavailable (e.g., running as a subagent), proceed without it.

Follow this loop for every task.

### 1. Pick the Task

Read `AGENTS/TODO.md`.
Identify the highest-priority item that is not blocked.
Prefer items that unblock other work.

Call `todowrite` to register the loop steps for this task (Plan, Write Tests, Implement, Update Docs, Commit).
Mark each step `in_progress` / `completed` as you go.

### 2. Plan

Before writing any code:
- Prepend **IN PROGRESS** to the item in `AGENTS/TODO.md`
- For non-trivial tasks, create a design document in `AGENTS/design/` following the global design document lifecycle conventions (NNN numbering, status line)
- For trivial tasks, a mental plan is sufficient — no design doc needed

### 3. Write Tests First

- Write the test that exercises the new/changed behavior *before* implementing
- For bug fixes, write a test that reproduces the bug and verify it fails
- Run the full test suite — only your new test should fail

If the project has no test suite (check `AGENTS/WORKFLOW.md` for overrides), skip this step or discuss with the user what testing framework fits the project.

### 4. Implement

- Make the code change, keeping it minimal and focused
- Run the test suite — all tests must pass
- Update build configuration if adding new files

### 5. Update Documentation

- Remove the completed task from `AGENTS/TODO.md`
- Update `AGENTS/ARCHITECTURE.md` if APIs, architecture, or system state changed — clean out any content the completed task made obsolete.
  ARCHITECTURE.md must always read as a present-tense description of the system.
- Update `AGENTS/WORKFLOW.md` if build/test/deploy procedures changed
- Update `AGENTS.md` index if new files or markers were added
- If the task had a design doc in `AGENTS/design/`, decide: archive it (move to `AGENTS/archive/` with archive date) or keep it active if phases remain
- Add any newly discovered issues to `AGENTS/TODO.md` and call `todowrite` for visibility

### 6. Commit and Repeat

Create an atomic commit, then return to step 1.
