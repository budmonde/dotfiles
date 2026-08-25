---
name: workspace-memory-protocol-feature-development
description: Develop medium-to-large features in a Workspace Memory Protocol workspace, from evidence and design through proportionate verification and memory reconciliation. Do not use for trivial fixes or work outside a WMP-managed workspace.
---

# Workspace Memory Protocol feature development

Use this skill to deliver a substantial WMP-tracked change without losing the reasoning, verification evidence, or follow-up work that make it maintainable.

`workspace-memory-protocol` defines the memory model, artifact lifecycle, and cross-reference rules.
`workspace-memory-protocol-migration` handles structural protocol upgrades and legacy conversions.
This skill applies the core protocol to feature delivery; it does not repeat or override it.

## Start from the workspace

Load `workspace-memory-protocol`, then the workspace index.
The index identifies the memory root, repository boundaries, local overrides, and the canonical locations for the todo list, tickets, roadmap, design documents, research, and architecture.
Do not assume the default `AGENTS/` layout when the workspace declares another root, such as `wiki/`.

Use this skill when the work changes a meaningful behavior, spans several files or steps, implements an accepted design, or resolves a tracked item.
Do not use it for an obvious one-file fix, routine cleanup, or an open-ended investigation.
For investigation-shaped work, create or extend a research artifact first and return here once a decision is possible.

## Establish the delivery shape

Before implementation, identify the source task and the expected outcome.
Use the highest-priority unblocked workspace todo item, an open ticket, or a roadmap-backed commitment unless the user has supplied a more specific task.

Choose the lightest durable planning artifact that preserves the necessary decision:

- **Research artifact** when the task requires discovering what is true before choosing a direction.
- **Design document** when a non-trivial decision, interface, tradeoff, or phased implementation needs to be recorded before the change lands.
- **No new artifact** when the work is small enough that the task statement and code review provide adequate context.

Mark the active todo item or ticket as in progress when the workspace uses that convention.
Use the current runtime's task or progress facility when one is available, but do not require a tool name or a particular status syntax.
The workspace todo and artifacts remain the cross-session record; runtime task state is only a session-local aid.

## Implement with proportionate evidence

Define the observable behavior that should change before implementation.
When the project has a suitable automated harness, add or update a focused test before or alongside the implementation and use it to demonstrate the intended result.
When automated testing is unavailable or unsuitable, follow the workspace's declared validation method and record enough evidence for a reviewer to understand what was checked.

Keep the change narrow and respect project-specific build, generation, deployment, and safety instructions.
If an unrelated pre-existing failure appears, stop to determine whether the feature introduced it.
Fix a regression caused by the change; otherwise preserve the evidence and create or update a follow-up task rather than silently absorbing unrelated work.

## Reconcile workspace memory

After the implementation and validation are complete, update only the memory substrates made stale by the change:

- Remove the completed workspace todo item rather than checking it off.
- Update the architecture document when current behavior, APIs, or system structure changed.
- Update an operational skill when its procedure, command, or validation method changed.
- Remove a resolved tracked deviation from the roadmap or record a newly discovered one.
- Reconcile the related design document, research artifact, or ticket according to the core WMP lifecycle.

Use artifact handles in live prose and task records.
Use frozen archive paths only where the WMP provenance rule calls for them, such as commit-message citations.
Do not update the index merely to enumerate individual artifacts; update it only when its structural map, skill catalog, or workspace guidance changed.

## Finish deliberately

Review the changed code, validation evidence, and affected memory before handoff.
Summarize what changed, how it was verified, and any remaining follow-up or operational risk.

When the user has authorized a commit, keep each commit to one logical change and read the target repository's root `COMMIT_POLICY.md` when it exists.
When it does not, follow the default commit policy rather than inheriting a workspace or sibling repository convention.
For foundational-document amendments, include the reason, the driving handle or session, and the relevant archived-research paths required by WMP provenance.
When commit authority has not been given, leave the work uncommitted and report the review surface instead.
