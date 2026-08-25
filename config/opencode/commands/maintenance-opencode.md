---
description: Audit codex-ctl's OpenCode 1.18.16 connector and integration contract for upstream changes
---
Run maintenance checks on OpenCode-related components in this dotfiles repository.

## Tasks

### 1. Check Plugin API Compatibility

Use public OpenCode `1.18.16` as the compatibility baseline:

- Review the matching `@opencode-ai/plugin` and `@opencode-ai/sdk` contracts.
- Review changelog or release notes before proposing a baseline upgrade.
- Compare hook signatures with
  `codex-ctl/app-server/opencode-connector.mjs` and normalized event handling
  with `codex-ctl/src/opencode-events.mjs`.

### 2. Review Recent Upstream Changes

Check OpenCode GitHub repository (https://github.com/anomalyco/opencode):
- List recent merged PRs (last 2 weeks) touching `packages/plugin/`, `packages/sdk/`, or event-related files
- Summarize any changes to event types, hook signatures, or plugin lifecycle
- Search for open issues with high activity related to plugins, breaking changes, or events

Use these queries if `gh` CLI is available:
```bash
# Merged PRs affecting plugin API (last 14 days)
gh pr list --repo anomalyco/opencode --state merged --limit 50 \
  --search "merged:>$(date -d '14 days ago' +%Y-%m-%d)" \
  --json number,title,files | jq '.[] | select(.files[]?.path | test("plugin|sdk|event"))'

# High-traffic plugin issues
gh issue list --repo anomalyco/opencode --state open --limit 30 \
  --search "label:plugin OR label:breaking OR event in:title" \
  --json number,title,comments,reactions | jq '.[] | select(.comments > 5 or .reactions.total_count > 10)'
```

### 3. Sync with Community Plugin Patterns

Fetch and analyze well-maintained reference plugins:
- https://github.com/mohak34/opencode-notifier
- https://github.com/kdcokenny/opencode-notify

Compare their event handling patterns with codex-ctl's implementation:
- Events handled (and how)
- Debouncing/deduplication strategy
- Session ID extraction patterns
- Error filtering (e.g., skipping MessageAbortedError)
- Any new patterns or bug fixes

### 4. Generate Compatibility Report

Produce a report with:
- **Breaking changes** that affect our plugin (with specific code changes needed)
- **New features/events** we should consider adopting
- **Deprecation warnings** with timelines
- **Pattern improvements** worth adopting

### 5. Update Local Components

If changes are needed:

- Update the OpenCode adapter or packaged connector in `codex-ctl`.
- Update `codex-ctl/src/runtime-integrations.mjs` when normalized integration
  behavior changes.
- Update `bin/push-notify*` only if the provider-neutral notification sink
  changes.
- Add or update controller tests for the pinned compatibility contract.
- Record a baseline change in codex-ctl's WMP documents before upgrading.

## Component Locations

### Controller-owned OpenCode integration

- **Connector**: `codex-ctl/app-server/opencode-connector.mjs`
- **Event adapter**: `codex-ctl/src/opencode-events.mjs`
- **Integration service**: `codex-ctl/src/runtime-integrations.mjs`
- **Private policy**: `local/codex-ctl/config.json`

### Push-notify Script
- **Unix script**: `bin/push-notify`
- **Windows script**: `bin/push-notify.ps1`
- **Windows launcher**: `bin/push-notify.cmd`

## Events the controller handles

| Event | Type | Purpose |
|-------|------|---------|
| Completion | `event: session.idle` | Task finished (350ms delay) |
| Error | `event: session.error` | Error occurred (skip MessageAbortedError) |
| Permission | `event: permission.asked` | Approval needed |
| Question | `hook: tool.execute.before` (`tool=question`) | User input needed |

## Connector hook signatures

Based on OpenCode docs (https://opencode.ai/docs/plugins):

```typescript
// Event handler
event: async ({ event }) => { ... }

// Tool hooks (input/output pattern, modify output in place)
"tool.execute.before": async (input, output) => { ... }
"tool.execute.after": async (input, output) => { ... }

// Shell env hook
"shell.env": async (input, output) => { ... }
```

## Notification Features by Platform

| Feature | WSL | macOS | Linux |
|---------|-----|-------|-------|
| Basic notification | ✓ | ✓ | ✓ |
| Custom sound | ✓ | ✓ | ✗ |
| Click-to-focus pane | ✓ | ✗ | ✗ |
| Silent mode | ✓ | ✓ | ✗ |
