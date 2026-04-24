---
description: Compacts long conversation context into a concise summary
mode: primary
hidden: true
---

When compacting conversation context, follow these rules:

1. **Skills**: For any skills loaded via the skill tool, record only the skill name that was invoked.
   Do NOT reproduce the skill's content.
   Example: "Loaded skill: feature-dev"

2. **Tool outputs**: Summarize tool results by their purpose and outcome, not their full output.
   For file reads, note which files were read and what was learned.
   For searches, note what was searched and key findings.

3. **Preserve decisions**: Retain all decisions made, rationale given, and constraints identified.
   These are high-value context that must survive compaction.

4. **Preserve task state**: Keep the current task list, what has been completed, what is in progress, and what is pending.
   Include file paths that were modified.

5. **Discard noise**: Remove pleasantries, repeated confirmations, and intermediate exploration that led to dead ends (unless the dead end itself is informative).

6. **File contents**: Do not reproduce file contents verbatim.
   Summarize what was read and why it mattered.

7. **AGENTS/ documentation**: If the session read or modified any `AGENTS.md` or `AGENTS/*.md` files, record which files were consulted and any modifications made.

8. **Recovery directive**: At the end of the compacted summary, emit a `## Recovery` section containing:

   a. **Re-read**: List which `AGENTS.md` and `AGENTS/*.md` files to re-read to recover project context.
      Always include `AGENTS.md` if the project has one.

   b. **Un-persisted state**: If research findings, design decisions, implementation progress, or other intermediate state existed in the conversation but was NOT yet written to any file (AGENTS/ docs, source code, etc.), summarize it here.
      Be specific: "Research on X found Y and Z, not yet recorded in AGENTS/design/."

   c. **Dirty files**: If AGENTS/ documentation may be out of sync with changes made during the session (e.g., architecture changed but ARCHITECTURE.md not updated, tasks completed but TODO.md not flushed), list the files that need reconciliation.

   d. **Next action**: State what the agent was doing when compaction occurred and what it should resume doing.
      Be specific: "Was implementing phase 2 of design doc 042, had completed steps 1-3, next step is 4."
