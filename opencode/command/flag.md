---
description: Flag the current session's most recent assistant turn as exhibiting an anti-pattern. Argument is a short free-text description.
---

Read the parent session id from the `OPENCODE_SESSION_ID` environment variable using the `bash` tool:

```powershell
echo $env:OPENCODE_SESSION_ID
```

Then dispatch the `flag-logger` subagent via the `task` tool with this prompt body, splicing in the captured session id:

```text
PARENT_SESSION_ID: <captured value>

OPERATOR_DESCRIPTION: $ARGUMENTS
```

Surface the subagent's reply unmodified.
Do not add commentary.
