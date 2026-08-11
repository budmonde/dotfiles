---
description: Audit the current session for un-persisted state and reconcile AGENTS/ documentation
---

Audit the current conversation for findings, decisions, and changes that have not been persisted to AGENTS/ documentation.
This command is useful after compaction, at the end of a long session, or when you suspect AGENTS/ docs have drifted from reality.

## Process

### 1. Inventory What Happened

Scan the conversation history (or compaction summary if post-compaction) and identify:
- **Files modified**: Source code, config, build files, etc.
- **Architecture changes**: New components, changed APIs, modified data flow
- **Decisions made**: Design choices, rejected alternatives, rationale
- **Research findings**: Investigation results, analysis, benchmarks
- **Tasks completed**: Items from `todo.md` that were finished
- **Tasks discovered**: New issues, bugs, or follow-up work identified
- **Design doc activity**: Design documents created, updated, or whose status changed
- **Research artifact activity**: Research chronicles, syntheses, or WAL files created, appended to, or sealed

### 2. Check AGENTS/ State

Read the current AGENTS/ documentation and check for drift:

| File | Check |
|------|-------|
| `AGENTS.md` | Is the structural map still accurate? Are markers current? Note: the index should NOT enumerate individual design docs or archive entries — those are discovered via `ls`. |
| `mission.md` | Has any change in principles, scope, or non-goals been surfaced that needs to land here? Mission edits should be rare and carry provenance in their commit message. |
| `architecture.md` | Does it reflect architectural changes made this session? Any stale references to old components? Any resolved issues still listed? |
| `workflow.md` | Do build/test/deploy instructions still work? Any new procedures? |
| `roadmap.md` | Are tracked deviations current? Any new deviations from `mission.md` surfaced this session? |
| `todo.md` | Are completed items flushed? Are new discoveries added? Is the dependency map current? Use `#DOC<NNN>` handle form for design-doc references. |
| `design/*.md` | Do status lines reflect current state? Should any docs move to `archive/` with the `YYYY-MM-DD_<handle>_<title>.md` naming? |
| `research/*.md` | Are any research artifacts no longer the canonical source for downstream work and ready to archive? Has any artifact been superseded by a newer synthesis? |
| `tickets/*.md` | Are any tickets resolved this session and ready to archive? |

### 3. Report

Present findings to the user as a table:

```
| Item | Status | Action Needed |
|------|--------|---------------|
| ... | Synced / Drifted / Missing | Description of fix |
```

### 4. Reconcile

After user confirmation, make the updates:
- Flush completed items from `todo.md`
- Add newly discovered tasks to `todo.md`
- Update `architecture.md` with any architectural changes
- Update `workflow.md` if procedures changed
- Update `roadmap.md` if new deviations surfaced
- Update design doc status lines
- Move completed design docs to `archive/` with `YYYY-MM-DD_DOC<NNN>_<title>.md` naming (archival date prefix)
- Seal research artifacts ready for archival by appending a final entry that names the seal cause (e.g. "Sealed: informed `#DOC<NNN>`" or "Superseded by `#RES<NNN>`"), then move to `archive/` with `YYYY-MM-DD_RES<NNN>_<title>.md` naming
- Move resolved tickets to `archive/` with `YYYY-MM-DD_TKT<NNN>_<title>.md` naming
- Update `AGENTS.md` structural map if directories were added or removed (do not enumerate individual docs)
- Write un-persisted research findings to an appropriate research artifact in `research/` (or fold into an existing design doc if the finding is decision-shaped rather than investigation-shaped)

### 5. Summary

Report what was updated and confirm AGENTS/ is now in sync with the project state.
