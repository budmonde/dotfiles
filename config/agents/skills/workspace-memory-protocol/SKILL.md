---
name: workspace-memory-protocol
description: Maintain persistent workspace memory through an index, foundational documents, operational skills, and durable artifacts. Use when bootstrapping or changing WMP-managed memory; not for ordinary project changes.
---

# Workspace Memory Protocol

## Decide whether WMP applies

Use this skill for multi-step or durable workspace work, existing WMP documentation, or changes to the workspace's memory model.
Do not use it for an ordinary isolated code change that has no memory consequence.

At session entry and after compaction, read the workspace index first and then only the documents relevant to the task.
If a durable workspace needs WMP but has no index, ask the user before bootstrapping it.
If an existing workspace has an earlier layout or operational model, use `workspace-memory-protocol-migration` rather than inventing a one-off conversion.
For a substantial feature in a current WMP workspace, also use `workspace-memory-protocol-feature-development`.

## Preserve the memory model

The context window is short-term memory.
The index, foundational documents, skill packages, and artifacts are durable on-disk memory.
Git history is durable provenance.

Keep the index small and navigational.
Keep foundational documents current rather than turning them into changelogs.
Remove completed todo items instead of checking them off.
Do not recreate `workflow.md`:
operational knowledge belongs in narrowly triggered, source-controlled skills.

The default single-repository layout is:

```text
AGENTS.md
AGENTS/
  mission.md
  architecture.md
  roadmap.md
  todo.md
  design/
  research/
  tickets/
  archive/
skills/
```

An index plus `todo.md` is the minimum.
Add other foundational files and artifact directories only when the workspace needs them.
Multi-repository or relocated layouts are valid only when their index declares the scope, location, and loader configuration.

## Keep responsibilities distinct

| Substrate | Keep it responsible for |
| --- | --- |
| Index | Quick reference, structural map, workspace-specific overrides, and optional targeted anchors. |
| `mission.md` | Stable identity, principles, goals, non-goals, and scope boundaries. |
| `architecture.md` | Present-tense current state, including only behavior and structure that are true now. |
| `roadmap.md` | Future direction and tracked deviations from mission principles until resolved or the principle changes. |
| `todo.md` | Actionable cross-session work only. |
| Skills | Environment, build, test, release, audit, and other operational procedures. |
| `COMMIT_POLICY.md` | Optional repository-local commit contract for subjects, provenance, scope, and reservations; it is not an operational skill. |
| Artifacts | Durable design decisions, research evidence, and inbound tickets. |

The index lists foundational documents and artifact directories, not every individual artifact.
Use the artifact forms and lifecycle rules in [`references/artifact-lifecycle.md`](references/artifact-lifecycle.md) when creating, changing, or closing artifacts.

## Keep skill sources with their owners

Author and vendor each operational skill where its owning repository can maintain it.
For this dotfiles workspace, ordinary repository skills live under `skills/<name>/`,
wiki-owned skills under `wiki/skills/<name>/`,
and shared WMP skills under `common/config/agents/skills/<name>/`.

Install vendor skills into a workspace with Skilltap.
The source path is not the runtime installation path.
Do not author source skills under `.agents/skills` because that directory is runtime state.
Record each installed skill's purpose, source, scope, and installation method in the workspace index or its referenced catalog.

## Preserve artifact identity

Use independent, permanently issued `DOC`, `RES`, and `TKT` counters with zero-padded numbers.
Use lowercase `snake_case` titles.
Reference local artifacts as `#DOC042`, `#RES017`, or `#TKT008`.
Prefix a cross-workspace reference with the workspace name, such as `dotfiles#DOC042`.

Active artifact names begin with their handle.
Archived artifact names begin with the archival date and retain the handle.
Resolve an artifact across active and archived locations with a handle glob such as `*DOC042_*.md`.
Update path-form citations when an artifact moves; handle-form citations remain stable.

## Reconcile before handoff

After significant work, update only the memory substrates affected by the change:

- Make `architecture.md` describe current reality, with obsolete workarounds removed.
- Correct the operational skill that owns any changed procedure.
- Update the target repository's `COMMIT_POLICY.md` when its commit contract changes; otherwise let the default commit policy apply.
- Remove completed `todo.md` items and keep live dependencies visible.
- Update `roadmap.md` deviations, artifact status, and archival state when applicable.
- Keep the index structural map and skill catalog accurate without fabricating unused directories.

When a significant chunk of work changes the workspace, offer an integrity audit of its memory.
Audit for accuracy, staleness, redundancy, lifecycle state, and consistency with `mission.md`.

## Avoid

- Keeping a WMP changelog, stale struck-through prose, or completed todo items.
- Recreating `workflow.md` instead of authoring an operational skill.
- Enumerating individual artifacts in the index.
- Reusing a retired handle or using path-only cross-workspace citations.
- Creating uppercase content filenames inside the documentation directory.
- Rewriting an archived research artifact after it has been sealed.
