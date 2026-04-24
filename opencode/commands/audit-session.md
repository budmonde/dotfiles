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
- **Tasks completed**: Items from TODO.md that were finished
- **Tasks discovered**: New issues, bugs, or follow-up work identified
- **Design doc activity**: Design documents created, updated, or whose status changed

### 2. Check AGENTS/ State

Read the current AGENTS/ documentation and check for drift:

| File | Check |
|------|-------|
| `AGENTS.md` | Does the index still reflect all AGENTS/ files? Are markers current? |
| `ARCHITECTURE.md` | Does it reflect architectural changes made this session? Any stale references to old components? Any resolved issues still listed? |
| `WORKFLOW.md` | Do build/test/deploy instructions still work? Any new procedures? |
| `TODO.md` | Are completed items flushed? Are new discoveries added? Is the dependency map current? |
| `design/*.md` | Do status lines reflect current state? Should any docs move to archive/? |

### 3. Report

Present findings to the user as a table:

```
| Item | Status | Action Needed |
|------|--------|---------------|
| ... | Synced / Drifted / Missing | Description of fix |
```

### 4. Reconcile

After user confirmation, make the updates:
- Flush completed items from TODO.md
- Add newly discovered tasks to TODO.md
- Update ARCHITECTURE.md with any architectural changes
- Update WORKFLOW.md if procedures changed
- Update design doc status lines
- Move completed design docs to archive/
- Update AGENTS.md index if files were added/removed
- Write un-persisted research findings to an appropriate design doc

### 5. Summary

Report what was updated and confirm AGENTS/ is now in sync with the project state.
