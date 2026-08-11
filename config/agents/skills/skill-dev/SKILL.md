---
name: skill-dev
description: Workflow for developing and maintaining opencode SKILL definitions
---

## What This Skill Does

This skill guides the development and maintenance of opencode SKILL.md files. It ensures skills are well-structured, cover edge cases, and remain clear and non-redundant as they evolve.

## When to Use

Use this skill when:
- Creating a new SKILL definition
- Modifying an existing SKILL
- Reviewing a SKILL for quality

Do NOT use for:
- Writing non-skill documentation (AGENTS.md, README, etc.)
- Implementing the behavior a skill describes — this skill develops the SKILL.md file itself, not the workflows it instructs

## Skill Development Workflow

Use OpenCode's `todowrite` tool throughout this workflow to maintain TUI visibility of progress. Update item statuses as you work — mark items `in_progress` when starting them and `completed` when done. If user feedback or edge case discovery adds work, call `todowrite` to track the new items rather than losing track of them. After any modification to a SKILL.md file, call `todowrite` to add a "Validate the Entire Skill" item (status `pending`) to ensure validation is never skipped. Use `todoread` to recover the current task state after context compaction or when resuming work. If `todowrite` is unavailable (e.g., running as a subagent), proceed without it — the workflow steps themselves are sufficient.

### 1. Gather Requirements

Before writing, understand what the skill should do:
- What problem does it solve?
- When should an agent use it vs. not use it?
- Are there existing workflows or patterns to base it on?

If basing on an existing workflow (e.g., from a project's AGENTS.md), read and understand that source first.

After gathering requirements, call `todowrite` to initialize progress with the workflow steps that apply to this task (e.g., Draft, Identify Edge Cases, Iterate, Validate). For modifications to an existing skill, start from the relevant step.

### 2. Draft the Initial Skill

Create the SKILL.md with required frontmatter (`name`, `description`) and initial content. Structure typically includes:
- What the skill does
- When to use / not use
- Core workflow or instructions
- Any setup or prerequisites

### 3. Identify Edge Cases

After drafting, think through edge cases:
- What if expected files/structure don't exist?
- What if the project has non-standard conventions?
- What about monorepos or subprojects?
- What if the user's context differs from assumptions?

**Ask the user** if they'd like to address any identified edge cases before proceeding.

### 4. Iterate with User Feedback

As the user requests changes:
- Add/edit/delete content as needed
- After each change, consider whether it introduces new edge cases

### 5. Validate the Entire Skill (Mandatory)

**This step is not optional. Run it after every modification, no matter how small — even a single-line edit.** Small changes can introduce inconsistencies, redundancies, or ordering problems that are invisible at the edit site but obvious when reading the full file.

Before starting, call `todowrite` to add or update a "Validate the Entire Skill" item with status `in_progress`. This item must not be marked `completed` until the full re-read and all quality checks below have passed.

Re-read the entire SKILL.md from top to bottom and evaluate against all quality axes:

**Flow and Organization**
- Do sections appear in logical order?
- Is prerequisite information presented before it's needed?
- Are related concepts grouped together?

**Clarity and Precision**
- Is the language precise and unambiguous?
- Are instructions actionable?
- Would an agent know exactly what to do?

**Redundancy**
- Are any concepts repeated across sections?
- Can sections be consolidated without losing information?
- Are there unnecessary words or phrases?

**Completeness** (from the Quality Checklist)
- Frontmatter has `name` and `description`
- `name` matches directory name, is lowercase with hyphens
- `description` is concise but specific (1-1024 chars)
- "When to use" and "When NOT to use" are clear
- Edge cases are addressed or explicitly noted as out of scope
- Instructions are actionable, not vague
- No redundant sections or repeated information
- Flow is logical — prerequisites before usage
- Project-specific overrides are accommodated where relevant

If issues are found, fix them (or suggest a refactor to the user) before considering the change complete. When reviewing a skill you cannot modify (e.g., a third-party or read-only skill), report all findings to the user instead.

### 6. Update This Skill (Meta-Maintenance)

When developing a skill reveals new insights about skill development itself:
- Call `todowrite` to add an "Evaluate whether insight applies to skill-dev" item with priority `medium`
- If the insight applies generally, propose updating this `skill-dev` SKILL to capture the new pattern
- This prevents future blindsiding by incorporating learned workflows

## Common Patterns

**Handling missing prerequisites**: Instruct the agent to consult with the user to create them, not just fail or skip.

**Project-specific overrides**: Note that the project's AGENTS.md or similar can override skill defaults, and that those overrides take precedence.

**Subproject scope**: For skills that involve file structures, consider that monorepos may need per-subproject application.

**Lean context**: Prefer structures that keep frequently-loaded files small, with detailed content in separate files loaded on demand.

## Anti-Patterns to Avoid

- **Vague instructions**: "Handle errors appropriately" — instead, specify how
- **Assumed context**: Don't assume files exist; handle missing cases
- **Monolithic skills**: If a skill is getting very long, consider whether it's actually multiple skills
- **Redundant sections**: Consolidate related content rather than repeating
- **Buried prerequisites**: Put setup/requirements near the top, not at the end
