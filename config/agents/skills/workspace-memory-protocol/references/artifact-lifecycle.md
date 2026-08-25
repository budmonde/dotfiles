# Artifact lifecycle and document forms

Use this reference when creating, advancing, resolving, or archiving WMP documents.

## Foundational document forms

The index stays small:
quick reference,
a structural map of foundational documents and artifact directories,
workspace-specific workflow overrides,
and optional targeted anchors.
It does not enumerate individual design documents, research artifacts, tickets, or archives.

`mission.md` is stable and slow-changing.
It records project identity, principles, goals, non-goals, and boundaries rather than current mechanisms or future plans.

`architecture.md` describes only current reality in present tense.
After a system change, remove obsolete issues and workarounds rather than striking them through.

`roadmap.md` records future direction and tracked deviations.
Each deviation identifies the mission principle, the current divergence, and the intended response.
Remove it only after resolution or a revision to that principle.

`todo.md` contains actionable work using this form:

```markdown
## <Category>

- [P0] Critical task description
- **IN PROGRESS** [P1] Task currently being worked on
- **SKIP** [P2] Task excluded from automated implementation
- [P2] Lower-priority task (blocked by: #DOC<NNN>)
```

Use `[P0]`, `[P1]`, and `[P2]` for critical, important, and nice-to-have work.
The runtime task list is only an intra-session overlay.
Delete completed todo items.
When design work has dependencies, keep the dependency map in `todo.md`.

## Naming and references

`DOC`, `RES`, and `TKT` counters advance independently.
Numbers are zero-padded to at least three digits and are never reused.
If a workspace passes 999, migrate that prefix to four-digit padding once.

Use these active names:

- `design/DOC<NNN>_<title>.md`
- `research/RES<NNN>_<title>.md`
- `tickets/TKT<NNN>_<title>.md`

Use this archive name:

```text
archive/YYYY-MM-DD_<handle>_<title>.md
```

The archive date is the date the artifact left the active workspace.
Titles are concise lowercase `snake_case`.

## Design documents

Every design document begins with:

```text
Status: Stub | Draft | In-Progress | Complete (archived YYYY-MM-DD)
```

Its lifecycle is `Stub → Draft → In-Progress → Complete → Archived`.
Stubs, drafts, and in-progress documents remain in `design/` as `DOC<NNN>_<title>.md`.
On completion, resolve or decide every open question, extract remaining work to `todo.md` or a successor design document, change the status line, and move the document to `archive/YYYY-MM-DD_DOC<NNN>_<title>.md`.

Phases may archive independently.
Track dependencies between active design documents in `todo.md`.

## Research artifacts

Research artifacts are append-only investigation records.
They do not carry a status line:
their active or archived location expresses their state.

Keep a research artifact active while it is the canonical source for ongoing work.
Before archiving it, append a final sealing entry that explains why it is closed, such as the decision it informed, the successor that supersedes it, or that no further appends are expected.
Then move it to the dated archive path and never rewrite it.
Use handle-form citations among active research and design artifacts so references survive archival renames.

## Tickets

Tickets are inbound messages that the receiving workspace owns.
Use this form:

```markdown
Status: Open | In-Progress | Resolved | Rejected
Filed-by: <project-name>
Date: YYYY-MM-DD

# TKT<NNN> - <Title>

<Description sufficient for the receiving project to understand and act.>

## Resolution

<Completed by the receiving project when resolved or rejected.>
```

Resolve or reject the ticket, record the resolution, and move it to the dated archive path.

## Provenance

Git history is the changelog for foundational documents.
Commits that amend `mission.md`, `architecture.md`, `roadmap.md`, or a design document driving one of those changes explain why the change was needed.
They cite the driving design document, ticket, or session by handle and cite informing archived research by frozen path.

For a structured bootstrap, commit in dependency order:
research artifacts first,
then `mission.md`,
then downstream foundational documents.
