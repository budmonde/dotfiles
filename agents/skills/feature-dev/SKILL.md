---
name: feature-dev
description: Structured workflow for developing medium-to-large features with documentation-first, test-driven development
---

## What This Skill Does

This skill provides a structured development loop for implementing features.
It ensures code changes are accompanied by tests, documentation stays current, and each commit is an atomic unit of work.

The `AGENTS/` directory structure, naming conventions, artifact lifecycles, and cross-reference rules are defined in the **global Project Memory Protocol** (PMP) in the global `AGENTS.md`.
This skill focuses solely on the development workflow that operates within that system; when in doubt about a memory or naming question, defer to the PMP rather than re-stating it here.

## When to Use

Use this skill when:
- Implementing a new feature that touches multiple files
- Making significant changes to existing functionality
- Working on tasks from `AGENTS/todo.md`, `AGENTS/tickets/`, or `AGENTS/roadmap.md`

Do NOT use for:
- Quick bug fixes (single file, obvious fix)
- Minor refactors or cleanup
- Exploratory or investigation-shaped work — produce a research artifact in `AGENTS/research/` instead, then return here once the work becomes decision-shaped

## Key Principles

1. **Documentation-first**: The plan exists as a design doc (or a mental plan for trivial tasks) before code exists.
2. **Test-driven**: Tests define expected behavior before implementation.
3. **Atomic commits**: Each commit is one logical unit of work. A single task may produce multiple atomic commits.

## Before Starting

The PMP handles bootstrap: if `AGENTS.md` and `AGENTS/` do not exist, follow the PMP's bootstrap prompt before invoking this skill.

Once memory exists, check the project's `AGENTS.md` and `AGENTS/workflow.md` for **workflow overrides** that take precedence over this skill's defaults. Common overrides:
- Different test commands or frameworks
- Specific commit message conventions
- Modified loop steps (e.g., skip tests for documentation-only changes)
- "No test suite" declaration

## The Development Loop

Use OpenCode's `todowrite` tool to maintain TUI visibility of progress within each loop iteration.
`AGENTS/todo.md` remains the canonical cross-session task list; `todowrite` is the ephemeral intra-session overlay.
If `todowrite` is unavailable (e.g., running as a subagent), proceed without it.

Follow this loop for every task.

### 1. Pick the Task

Identify the next unit of work. Sources, in priority order:
- An unblocked `[P0]` item in `AGENTS/todo.md`
- An open ticket in `AGENTS/tickets/` (treat the ticket as the task)
- A `[P1]`/`[P2]` item that unblocks other work

Call `todowrite` to register the loop steps for this task (Plan, Write Tests, Implement, Update Docs, Commit). Mark each step `in_progress` / `completed` as you go.

### 2. Plan

Before writing any code:
- Prepend `**IN PROGRESS**` to the item in `AGENTS/todo.md` (or update the ticket status to `In-Progress`).
- **Decide the artifact shape**:
  - **Investigation-shaped task** (you need to find out what's true before you can decide what to build): produce a research artifact in `AGENTS/research/` following the PMP's research-artifact rules, then re-evaluate whether the task is now decision-shaped.
  - **Decision-shaped non-trivial task**: create a design doc in `AGENTS/design/` per the PMP's design-document lifecycle.
  - **Trivial task**: a mental plan is sufficient; no artifact needed.
- If the task targets a **tracked deviation** in `AGENTS/roadmap.md`, note that the deviation will be resolved by this work.

### 3. Write Tests First

- Write the test that exercises the new/changed behavior *before* implementing.
- For bug fixes, write a test that reproduces the bug and verify it fails.
- Run the full test suite — only your new test should fail.

If the project has no test suite (check `AGENTS/workflow.md`), skip this step or discuss with the user what testing framework fits the project.

### 4. Implement

- Make the code change, keeping it minimal and focused.
- Run the test suite — all tests must pass.
- If a pre-existing test fails that your change did not target, **stop and investigate** before proceeding: either the change introduced a regression (fix it) or the prior test was broken (file a follow-up task in `AGENTS/todo.md`).
- Update build configuration if adding new files.

### 5. Update Documentation

- Remove the completed task from `AGENTS/todo.md` (do not check it off — delete it; git history is the record).
- Update `AGENTS/architecture.md` if APIs, architecture, or system state changed. Clean out any content the completed task made obsolete. `architecture.md` must always read as a present-tense description of the system.
- Update `AGENTS/workflow.md` if build/test/deploy procedures changed.
- Update `AGENTS/roadmap.md` if this task resolved a tracked deviation (remove the entry) or surfaced a new one (add it).
- Update `AGENTS.md` structural map **only** if directories were added or removed — never enumerate individual artifacts; those are discovered via `ls` and glob per the PMP.
- **Design doc disposition**: if the task had a design doc, decide per the PMP's lifecycle: archive it (move to `AGENTS/archive/` with the `YYYY-MM-DD_DOC<NNN>_<title>.md` archival-date prefix) or keep it active if phases remain.
- **Research artifact disposition**: if the task consumed a research artifact and that artifact is no longer the canonical source, **append a final seal entry** naming the seal cause per the PMP's research-artifact rules, then archive it.
- **Ticket disposition**: if the task resolved a ticket, fill in the ticket's `## Resolution` section, set status to `Resolved`, and archive with `YYYY-MM-DD_TKT<NNN>_<title>.md`.
- Use `#DOC<NNN>` / `#RES<NNN>` / `#TKT<NNN>` handle form when referencing artifacts in todo entries, prose, and commit message bodies.
- Add any newly discovered work to `AGENTS/todo.md` and call `todowrite` for visibility.

### 6. Commit and Repeat

Create one or more atomic commits, then return to step 1. Each commit is one logical unit; large tasks may legitimately produce multiple commits.

For commits that amend **foundational documents** (`mission.md`, `architecture.md`, `roadmap.md`, plus any design doc that drives such an amendment), write a commit message that:
- Captures the *why* (what surfaced the need).
- Cites the driving design doc, ticket, or session by handle (e.g. `addresses #DOC042`).
- Cites archived research or WAL artifacts that informed the decision by **path** (commit messages reference frozen paths; this is the one place path-form is preferred over handle-form, per the PMP's commit-discipline rule).

The commit message is the provenance trail; foundational docs do not keep their own changelog sections.
