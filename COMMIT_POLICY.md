# Commit policy

Commit tags identify the tool or subsystem whose capability changes.
They do not identify the file type, configuration layer, or kind of work performed.

Use `[TAG] Imperative subject` for one tool and `[TAG1/TAG2] Imperative subject` for one coherent multi-tool change.
Capitalize the first word after the closing bracket, use imperative mood, omit a trailing period, and use ASCII only.

Choose an uppercase tag from the tool's established name, or introduce a clear tool name when none exists.
The vocabulary is open-ended.
Tag by the capability being added, removed, fixed, or documented rather than by the manifest or profile that carries the change.
For example, adding `fzf` through a Dotbot profile uses `[FZF]`.

Use `[DOTBOT]` when the behavior or structure of Dotbot profiles, manifests, or deployment mechanics itself changes.
Use `[TEST]` when the test suite itself is the changed tool, such as its harness or generic test utilities.
Test coverage for a particular tool uses that tool's tag instead.

When one change genuinely changes multiple tools, list those tags in descending order of significance, such as `[GIT/POWERSHELL]`.
Split unrelated tool changes into separate commits.

`[META]` is reserved for a whole-repository migration or refactor.
