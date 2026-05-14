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

### 2. Filename Casing

The current protocol uses **lowercase** filenames inside `AGENTS/`.
For any uppercase core docs (`MISSION.md`, `ARCHITECTURE.md`, `WORKFLOW.md`, `TODO.md`, `ROADMAP.md`), rename to lowercase:
- `AGENTS/MISSION.md` → `AGENTS/mission.md`
- `AGENTS/ARCHITECTURE.md` → `AGENTS/architecture.md`
- `AGENTS/WORKFLOW.md` → `AGENTS/workflow.md`
- `AGENTS/TODO.md` → `AGENTS/todo.md`
- `AGENTS/ROADMAP.md` → `AGENTS/roadmap.md`

Update all path-form references inside other docs.
Leave the root `AGENTS.md` uppercase (community convention).

### 3. STATE.md → architecture.md + workflow.md

If `AGENTS/STATE.md` exists:
1. Read it fully and identify which sections are **architecture** (components, data flow, API surface, design decisions, directory layout, known issues) vs **workflow** (setup, build, test, deploy, environment, commands, conventions).
2. Present the proposed split to the user for confirmation.
3. Create `AGENTS/architecture.md` with architecture sections.
   Ensure it reads as present-tense description of the system.
4. Create `AGENTS/workflow.md` with workflow sections.
5. Delete `AGENTS/STATE.md`.

If content doesn't clearly fit either file, ask the user.

### 4. DONE.md → Flush

If `AGENTS/DONE.md` exists:
1. Read its contents and show the user.
2. Confirm that completed items can be discarded (git history preserves them).
3. Delete `AGENTS/DONE.md`.

### 5. scratch/ → design/

If `AGENTS/scratch/` exists:
1. Rename `AGENTS/scratch/` to `AGENTS/design/`.

### 5b. design/research/ → research/

If `AGENTS/design/research/` exists:
1. Move it to top-level `AGENTS/research/`.
2. Research artifacts are first-class in the current protocol, parallel to `design/` and `tickets/`.

### 5c. issues/ → tickets/

If `AGENTS/issues/` exists:
1. Rename to `AGENTS/tickets/`.
2. The directory name matches the `TKT<NNN>` handle.

### 6. SCRATCH_*.md → design/

If any `AGENTS/SCRATCH_*.md` files exist at the AGENTS/ root:
1. For each file, determine if it has lasting design value or is truly ephemeral.
2. Design-value files: move to `AGENTS/design/` with proper `DOC<NNN>_<title>.md` naming and a status line.
3. Ephemeral files: confirm deletion with the user.

### 7. REFACTOR.md → design doc

If `AGENTS/REFACTOR.md` exists:
1. Read it.
   If it contains or references a design document, migrate it into `AGENTS/design/` with proper `DOC<NNN>_<title>.md` naming.
2. If it's a short pointer to another doc, its content can be folded into `todo.md` instead.
3. Delete `AGENTS/REFACTOR.md` after migration.

### 8. FUTURE.md → roadmap.md

If `AGENTS/FUTURE.md` exists:
1. Rename to `AGENTS/roadmap.md`.

### 9. SETUP.md → workflow.md

If `AGENTS/SETUP.md` exists and `AGENTS/workflow.md` does not:
1. Rename `AGENTS/SETUP.md` to `AGENTS/workflow.md`.

If both exist, merge SETUP.md content into workflow.md and delete SETUP.md.

### 10. Design Doc Naming Convention

For all design docs in `AGENTS/design/` and `AGENTS/archive/`:
1. **Active design docs** in `AGENTS/design/` should follow `DOC<NNN>_<lowercase_title>.md`.
   - Legacy `NN_*.md` or `NNN_*.md` files: rename to `DOC<NNN>_<title>.md`, lowercase the title, retain the numeric portion as the handle.
   - If numbering crosses 999, do a one-time pad-to-4-digits migration.
2. **Archived design docs** in `AGENTS/archive/` should follow `YYYY-MM-DD_DOC<NNN>_<lowercase_title>.md`.
   - The date prefix is the **archival date** (when the doc moved to `archive/`).
   - If the original archival date is unknown, use the date of the last substantive edit, or the date of the migration itself with a note.
   - Same-day archivals tie in `ls`; that's fine — no disambiguation suffix is added.
3. **Tickets** in `AGENTS/tickets/` follow `TKT<NNN>_<lowercase_title>.md`. Resolved tickets move to `archive/` with `YYYY-MM-DD_TKT<NNN>_<title>.md`.
4. **Research artifacts** in `AGENTS/research/` follow `RES<NNN>_<lowercase_title>.md`. Archived artifacts move to `archive/` with `YYYY-MM-DD_RES<NNN>_<title>.md`.
   - Legacy research files without a handle: assign the next available `RES<NNN>` number (independent counter from `DOC` and `TKT`) and rename.
   - Research artifacts are write-ahead logs and do **not** carry a status header. Migration is structural only — do not append seal/supersession entries retroactively; the file's location (`research/` vs. `archive/`) is itself the status.
5. Ensure each design doc has a status line at the top.
   If missing, infer status from location (`design/` = Stub/Draft/In-Progress, `archive/` = Complete) and add it.
6. After renaming, update path-form references in other docs.
   Handle-form references (`#DOC042`, `#RES017`, `#TKT008`) keep resolving via glob automatically.

### 11. Cross-Reference Convention

Inside prose, commit messages, and design docs:
- Replace bare references like `"doc 042"`, `"042_FOO.md"` with the handle form `#DOC042`.
- Path-form references (`AGENTS/design/DOC042_foo.md`) remain valid for cases where a full path is more readable.

### 12. Update AGENTS.md

After all migrations:
1. **Slim the AGENTS.md index** — it should contain only a structural map of `AGENTS/` (the core files and the *directories* `design/`, `research/`, `tickets/`, `archive/`), not an enumeration of every design doc, research artifact, ticket, or archive entry.
   Agents discover the contents of those directories by listing them and resolve specific references by globbing on the handle (e.g. `glob **/*DOC042_*.md`, `glob **/*RES017_*.md`). The leading wildcard is required because archived files carry a `YYYY-MM-DD_` date prefix while active files do not.
2. Update any marker references (e.g., `STATE:topic` → section references in `architecture.md` or `workflow.md`).
3. Remove references to deleted files (`STATE.md`, `DONE.md`, `SETUP.md`, etc.).
4. Confirm the index reflects the new lowercase casing.

### 13. Summary

Report all changes made:
- Files created, renamed, deleted
- Content moved between files
- Naming-convention changes applied (casing, handle prefix)
- Any manual follow-ups needed
