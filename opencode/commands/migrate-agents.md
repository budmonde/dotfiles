---
description: Migrate a project's AGENTS/ directory from the old format to the current protocol
---

Migrate the AGENTS/ documentation in the current project (or the path specified in $ARGUMENTS) from the legacy format to the current Project Memory Protocol.

## Migration Steps

Scan the project root for `AGENTS.md` and `AGENTS/` directory.
Report what exists, then apply the following migrations.
**Always confirm with the user before making destructive changes** (deleting files, merging content).

### 1. Inventory

Read `AGENTS.md` and list all files in `AGENTS/`.
Report the current state:
- Which files exist
- Which migrations apply
- Proposed actions for each file

Ask the user to confirm before proceeding.

### 2. STATE.md → ARCHITECTURE.md + WORKFLOW.md

If `AGENTS/STATE.md` exists:
1. Read it fully and identify which sections are **architecture** (components, data flow, API surface, design decisions, directory layout, known issues) vs **workflow** (setup, build, test, deploy, environment, commands, conventions).
2. Present the proposed split to the user for confirmation.
3. Create `AGENTS/ARCHITECTURE.md` with architecture sections.
   Ensure it reads as present-tense description of the system.
4. Create `AGENTS/WORKFLOW.md` with workflow sections.
5. Delete `AGENTS/STATE.md`.

If content doesn't clearly fit either file, ask the user.

### 3. DONE.md → Flush

If `AGENTS/DONE.md` exists:
1. Read its contents and show the user.
2. Confirm that completed items can be discarded (git history preserves them).
3. Delete `AGENTS/DONE.md`.

### 4. scratch/ → design/

If `AGENTS/scratch/` exists:
1. Rename `AGENTS/scratch/` to `AGENTS/design/`.
2. Check if any design docs use 2-digit numbering (NN_).
   If so, offer to renumber to 3-digit (NNN_) for consistency.

### 5. SCRATCH_*.md → design/

If any `AGENTS/SCRATCH_*.md` files exist at the AGENTS/ root:
1. For each file, determine if it has lasting design value or is truly ephemeral.
2. Design-value files: move to `AGENTS/design/` with proper NNN naming and a status line.
3. Ephemeral files: confirm deletion with the user.

### 6. REFACTOR.md → design doc

If `AGENTS/REFACTOR.md` exists:
1. Read it.
   If it contains or references a design document, migrate it into `AGENTS/design/` with proper NNN naming.
2. If it's a short pointer to another doc, its content can be folded into TODO.md instead.
3. Delete `AGENTS/REFACTOR.md` after migration.

### 7. FUTURE.md → ROADMAP.md

If `AGENTS/FUTURE.md` exists:
1. Rename to `AGENTS/ROADMAP.md`.

### 8. SETUP.md → WORKFLOW.md

If `AGENTS/SETUP.md` exists and `AGENTS/WORKFLOW.md` does not:
1. Rename `AGENTS/SETUP.md` to `AGENTS/WORKFLOW.md`.

If both exist, merge SETUP.md content into WORKFLOW.md and delete SETUP.md.

### 9. Design Doc Numbering

For all design docs in `AGENTS/design/` and `AGENTS/archive/`:
1. Check naming convention.
   If using 2-digit (NN_), offer to renumber to 3-digit (NNN_).
2. Ensure each doc has a status line at the top.
   If missing, infer status from location (design/ = Stub/Draft/In-Progress, archive/ = Complete) and add it.

### 10. Update AGENTS.md Index

After all migrations:
1. Update the documentation index table in `AGENTS.md` to reflect new file names.
2. Update any marker references (e.g., `STATE:topic` → section references in ARCHITECTURE.md or WORKFLOW.md).
3. Remove references to deleted files (STATE.md, DONE.md, SETUP.md, etc.).

### 11. Summary

Report all changes made:
- Files created, renamed, deleted
- Content moved between files
- Numbering changes applied
- Any manual follow-ups needed
