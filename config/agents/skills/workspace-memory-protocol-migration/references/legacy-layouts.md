# Legacy layout mappings

Use this reference only after the migration inventory finds a matching legacy form.
These mappings target the current WMP, which replaces procedural `workflow.md` documents with focused skills.

## Legacy foundational documents

| Observed form | Current target | Migration notes |
|---|---|---|
| `AGENTS/MISSION.md`, `ARCHITECTURE.md`, `TODO.md`, or `ROADMAP.md` | Lowercase counterpart in `AGENTS/` | Rename and update path-form references. Keep root `AGENTS.md` uppercase. |
| `AGENTS/WORKFLOW.md` or `AGENTS/workflow.md` | One or more scoped skills, plus foundational documents and optional `COMMIT_POLICY.md` where appropriate | Inventory every procedure before moving content. Move a repository-specific commit convention to the repository root; do not rename the document to a new lowercase workflow file. |
| `AGENTS/STATE.md` | `architecture.md` plus skills and optional `COMMIT_POLICY.md` | Put present-tense components, data flow, APIs, decisions, layout, and current issues in architecture. Move setup, build, test, deploy, and commands to scoped skills; move repository-specific commit rules to the root policy. Present the split for confirmation. |
| `AGENTS/DONE.md` | Git history | Confirm before deletion. Completed work is not copied into todo. |
| `AGENTS/FUTURE.md` | `roadmap.md` | Rename or merge after confirming the document is future direction rather than active work. |
| `AGENTS/SETUP.md` | One or more scoped skills | Treat it as operational-model drift, not as a workflow-file rename. Merge only the still-current procedures after confirmation. |
| `AGENTS/REFACTOR.md` | Design document or todo | Move a durable proposal to `design/` with a `DOC` handle. Fold a short pointer or remaining actions into the workspace todo. |

## Legacy directories and loose documents

| Observed form | Current target | Migration notes |
|---|---|---|
| `AGENTS/scratch/` | `AGENTS/design/` | Rename when the contents are active design work. |
| `AGENTS/design/research/` | `AGENTS/research/` | Research is first-class, parallel to design and tickets. |
| `AGENTS/issues/` | `AGENTS/tickets/` | Rename and update references to the ticket namespace. |
| `AGENTS/SCRATCH_*.md` | `AGENTS/design/` or deletion | Move durable design material to `design/` with a handle and status line. Confirm before deleting ephemeral material. |
| Root-level operational notes | Appropriate scoped skill or foundational document | Classify content before moving it. Do not create a catch-all replacement file. |
| Legacy `Commit Convention`, `Commit Messages`, or provenance section | Repository-root `COMMIT_POLICY.md`, or the default policy | Preserve repository-specific tags, message shape, provenance, scope, and reservations in the root policy. Remove the legacy section when no repository-specific rule remains. |

## Artifact identity migration

Preserve an existing stable number whenever it unambiguously identifies an artifact.
`DOC`, `RES`, and `TKT` counters are independent, zero-padded, and permanent.
Assign a new number only after confirmation when a legacy artifact has no stable identity.

| Artifact | Active name | Archived name | Additional rule |
|---|---|---|---|
| Design | `design/DOC<NNN>_<title>.md` | `archive/YYYY-MM-DD_DOC<NNN>_<title>.md` | Add a status line if absent. Infer status from location only when the content supports it; otherwise ask. |
| Research | `research/RES<NNN>_<title>.md` | `archive/YYYY-MM-DD_RES<NNN>_<title>.md` | Do not add status lines or retroactive seal entries. Research is append-only, and location expresses its state. |
| Ticket | `tickets/TKT<NNN>_<title>.md` | `archive/YYYY-MM-DD_TKT<NNN>_<title>.md` | Preserve status and resolution information before archival. |

For legacy active design names such as `NN_*.md` or `NNN_*.md`, retain the numeric portion as the `DOC` number and lowercase the snake-case title.
For an archived design document, the date prefix is the archival date.
If it is unknown, use the last substantive-edit date or the migration date and record the uncertainty in the migration manifest.
If a project crosses 999 issued handles, perform a one-time pad-to-four migration for that prefix.

## References and index repair

Replace an unambiguous legacy artifact mention such as `042_foo.md` or `doc 042` with `#DOC042`.
Use `#RES042` and `#TKT042` for the other namespaces.
Update path-form references after any rename or move, including index anchors that point at a retired operational document.

Keep the index lightweight:

- Map foundational documents, artifact directories, and the skill catalog.
- Identify each workspace skill's purpose, scope, vendor location, and installation path.
- Do not enumerate every artifact; agents discover them through directory listings and handle globs.
- Remove retired entries such as `STATE.md`, `DONE.md`, `SETUP.md`, and `workflow.md` once the migration completes.
