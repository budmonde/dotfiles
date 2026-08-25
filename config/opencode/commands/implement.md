---
description: Implement all items from a TODO file using the Workspace Memory Protocol feature-development skill
---

You are given a TODO file to implement. The file path is: $ARGUMENTS

Here are the current contents of the TODO file:
!`cat $ARGUMENTS`

Load the `workspace-memory-protocol-feature-development` skill and follow its development loop for each item.

## Rules

1. Read the TODO file and collect all actionable items — skip any prefixed with **SKIP**.
2. Add each non-skipped item to your internal todo list.
3. As your **final internal todo item**, add: "Re-read $ARGUMENTS for remaining items and continue implementing." This ensures you return to the file after completing your current batch, picking up any items that didn't fit in the initial context.
4. Work through items one at a time using the WMP feature-development skill to choose the appropriate planning artifact, verification, memory reconciliation, and handoff.
5. After completing each item, remove it from the TODO file. Completed items are flushed — do not move them to a separate file.
6. When you reach the final "re-read" todo item, read the TODO file again. If non-skipped items remain, repeat from step 2. If only **SKIP** items or nothing remains, you are done.

Do not modify or implement **SKIP** items. Leave them in the TODO file as-is.
