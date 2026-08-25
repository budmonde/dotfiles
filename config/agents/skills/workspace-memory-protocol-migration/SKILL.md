---
name: workspace-memory-protocol-migration
description: Upgrade a workspace from any earlier Workspace Memory Protocol layout or operational model to the current protocol. Use for legacy AGENTS/wiki restructures, workflow.md-to-skills migrations, and future WMP drift; not for ordinary documentation edits.
---

# Workspace Memory Protocol migration

Use this skill to bring an existing memory system into conformance with the current `workspace-memory-protocol` skill without losing operating knowledge or falsifying history.

The current WMP is the target definition.
Do not rely on a document's claimed protocol version alone;
infer its migration needs from its index, layout, filenames, operational guidance, artifact conventions, and live references.

## Establish the migration boundary

Load `workspace-memory-protocol`, then the workspace index.
Identify the memory root, repository boundaries, source-owned skill catalog, runtime installation mechanism, and declared deviations from the default layout.
Treat archives and sealed research as historical records; do not rewrite them merely to adopt current terminology.

Inventory the live memory surface before editing.
For each discrepancy, record the observed form, current-WMP target, proposed transformation, information risk, and affected references.
Classify each as one of:

- **Already conformant** — verify and leave it alone.
- **Mechanical layout drift** — a safe casing or path rename with an unambiguous target.
- **Semantic split or merge** — content must be classified between destinations.
- **Operational-model drift** — procedures must move from a legacy document into scoped skills.
- **Ambiguous** — the target or destination cannot be inferred safely.

Read [legacy layout mappings](references/legacy-layouts.md) when any older AGENTS-era filenames, directories, or artifact names are present.

## Propose before destructive change

Present an explicit migration manifest before deleting files, merging content, retiring an operational document, or assigning new artifact handles.
For each operation, name the source, destination, whether content changes, references to update, and whether the old path will be removed.

Require user confirmation for deletion, content merges, uncertain classifications, and any handle assignment whose historical identity is unclear.
Do not use a migration to broaden authority for commits, external publication, or unrelated code changes.

## Apply the target model

Prefer the smallest change that reaches the current WMP.
Preserve stable artifact identities and update path-form references when a move changes them.
Handle-form references continue to resolve across archival renames and normally need no rewrite.

When migrating a legacy operational document, first inventory every procedure, command, safety condition, validation step, and escalation rule.
Move each current procedure to the narrowest useful source-owned skill:

- A repository or workspace skill for shared procedures.
- A documentation-root skill for memory maintenance, artifacts, and audits.
- A subproject skill only when sibling projects cannot use the procedure.

Do not recreate `workflow.md` in lowercase.
Retire it only after its applicable knowledge is represented by skills, their references, or the appropriate WMP foundational document.
Place current-state facts in architecture, future work in roadmap, and active tasks in todo rather than duplicating them in a skill.

Move a legacy commit-convention section to the target repository's root `COMMIT_POLICY.md` only when it defines a repository-specific contract.
Preserve its tag taxonomy, subject rules, provenance requirements, scope boundaries, and tag reservations there.
Do not convert commit policy into an operational skill.
When no repository-specific rule remains, remove the legacy section and let the default commit policy apply.

Source-owned workspace skills belong in the scope owner's declared vendor catalog, not `.agents/skills/`.
For example, an ordinary repository may vendor `skills/`, a wiki may vendor `wiki/skills/`, and shared WMP skills remain in the common agent-skill catalog.
Record each workspace skill's scope, vendor location, and installation path in the index.

## Make future drift manageable

Treat every future WMP change as a target-rule delta, not as a reason to invent a new migration command.
Compare the observed workspace against the changed rule, add a narrow migration mapping only when the observed legacy form is real, and keep unrelated layouts untouched.

If a future rule requires semantic interpretation, preserve the same manifest-and-confirmation boundary.
Add a new mapping to the legacy-layout reference only after it has a clear source signature, deterministic target, and verification method.

## Verify and hand off

Before completion:

- Validate every new or changed skill with the skill-authoring validator when available.
- Confirm the index, architecture, roadmap, todo, skill catalog, and runtime configuration describe the resulting workspace only.
- Search live files for old paths, filenames, headings, and operational entry points that the migration retired.
- Confirm every migrated repository-specific commit rule now lives in that repository's `COMMIT_POLICY.md`, with no workflow or sibling-workspace fallback left live.
- Verify artifact handles, archival prefixes, statuses, and path-form references affected by the migration.
- Confirm archived artifacts were not rewritten except for an authorized move or a necessary live-reference repair.

Report the applied manifest, validation evidence, unresolved ambiguities, and any follow-up that requires user judgment.
Leave the changes uncommitted unless the user has authorized a commit.
