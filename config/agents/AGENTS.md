# Global Agent Guidelines

## Coding Guidelines

### Comments

Do not add comments unless they explain non-obvious behavior, intent, or constraints that cannot be expressed through naming or structure.
In particular, do not:

- Narrate or restate what the code does (`// increment counter`, `# loop over users`).
- Add section-divider banners or decorative comments.
- Annotate edits with change-log prose (`// added retry`, `// fixed bug`, `// updated logic`).
  That belongs in the commit message.
- Add comments addressed to the user rather than future readers of the code.
- Add docstrings or header comments to trivial functions whose signature is self-explanatory.

Prefer clear, descriptive names over comments that restate the code.
When in doubt, omit the comment.

### Markdown Authoring

Whenever a markdown file is authored or edited, load the `markdown` skill and follow its formatting conventions.
This includes `AGENTS.md`, WMP files, README files, design documents, research artifacts, tickets, and other Markdown content.

### Shell Tools: Prefer `workdir` Over `git -C` and `cd`

When invoking Git or another tool against a directory other than the current working directory, use the shell tool's `workdir` parameter instead of composing a directory change in the command string.

Use `workdir: <path>` with a bare `git log ...` rather than `git -C <path> log ...`.
Use `workdir: <path>` with a bare command rather than chaining `cd <path>; <command>`.

The `workdir` parameter avoids command-allowlist matcher quirks that can reject otherwise equivalent `git -C` calls.
If a `git -C <path>` call is denied unexpectedly, retry it with `workdir` set to the same path before escalating.

## Workspace Memory Protocol

The Workspace Memory Protocol (WMP) is the canonical lifecycle and structure for persistent workspace memory.
Before bootstrapping or changing a workspace index, foundational document, operational skill, design document, research artifact, ticket, or memory layout, load the `workspace-memory-protocol` skill.

At session entry and after compaction, load the workspace index first.
It identifies the applicable memory root, repository boundaries, local deviations, and operational skills.

When a workspace uses an older memory layout or needs a structural WMP upgrade, use the `workspace-memory-protocol-migration` skill.
For a medium-to-large feature in a WMP-managed workspace, use `workspace-memory-protocol-feature-development`.
