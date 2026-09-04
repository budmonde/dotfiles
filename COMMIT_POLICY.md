# Commit policy

Commit tags identify the tool or subsystem whose capability changes.
They do not identify the file type, configuration layer, or kind of work performed.

Use `[TAG] Imperative subject` for one tool and `[TAG1/TAG2] Imperative subject` for one coherent multi-tool change.
Capitalize the first word after the closing bracket, use imperative mood, omit a trailing period, and use ASCII only.

Choose an uppercase tag from the tool's established name, or introduce a clear tool name when none exists.
The vocabulary is open-ended.
Tag by the capability being added, removed, fixed, or documented rather than by the manifest or profile that carries the change.
For example, adding `fzf` through a Dotbot profile uses `[FZF]`.

Use `[DOTBOT]` when the behavior or structure of Dotbot recipes, manifests, or deployment mechanics itself changes.
Use `[TEST]` when the test suite itself is the changed tool, such as its harness or generic test utilities.
Test coverage for a particular tool uses that tool's tag instead.

When one change genuinely changes multiple tools, list those tags in descending order of significance, such as `[GIT/POWERSHELL]`.
Split unrelated tool changes into separate commits.

`[META]` is reserved for a whole-repository migration or refactor.

## Scope visibility

This is a public repository.
Treat every added or renamed path, added line, commit subject, and commit body as publishable.

Reject a commit when an added line, added or renamed path, commit subject, or commit body discloses private-scope information, including:

- An employer or client name, affiliation, or scope marker.
- A private repository, branch, remote, project, cluster, host, service, gateway, resource, or endpoint.
- A private account, tenant, organization identifier, email address, username, machine name, or person-identifying path.
- Content copied or summarized from a private configuration whose existence or details are not already intentionally public.

Do not name or describe a private sibling repository or its contents.
Use generic seam language such as "a private overlay" when the integration boundary itself must be documented.

A public organization, product, service, or repository name is allowed only when it is necessary to configure or document that independently public dependency.
Do not use public names as personal examples, scope labels, or explanations of the operator's private environment.

Audit newly exposed information rather than removed information.
Unchanged context and deleted lines do not newly expose information.
A repository-internal move of already tracked content likewise does not newly expose content carried unchanged; evaluate its added lines and destination path.
Permit a change whose relevant effect is to remove an existing exposure.
When rejecting a scope violation, identify the path and the category of private information without repeating the private value in the rationale.
