---
description: Audit OpenCode plugin API for upstream changes and update local plugins accordingly
---
Run maintenance checks on OpenCode-related components in this dotfiles repository.

## Tasks

### 1. Check Plugin API Compatibility

Check the latest `@opencode-ai/plugin` and `@opencode-ai/sdk` packages:
- Fetch https://www.npmjs.com/package/@opencode-ai/plugin and note current version
- Review changelog or release notes for breaking changes
- Compare with patterns used in our plugin at `opencode/plugins/notify-on-idle.ts`

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

Compare their event handling patterns with ours:
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
- Update `opencode/plugins/notify-on-idle.ts` with fixes
- Update `shell/plugins/push-notify/` if notification script changes needed
- Update `scratch/notify-plugin-design.md` if design patterns change
- Test the plugin still works after changes

## Component Locations

### OpenCode Plugin
- **Plugin**: `opencode/plugins/notify-on-idle.ts`
- **Design doc**: `scratch/notify-plugin-design.md`

### Push-notify Script
- **Main script**: `shell/plugins/push-notify/bin/push-notify`
- **Backends**: `shell/plugins/push-notify/backends/` (wsl.sh, macos.sh, linux.sh)
- **Install**: `shell/plugins/push-notify/install`
- **WSL callback**: `shell/plugins/push-notify/bin/push-notify-callback`
- **Windows handler**: `shell/plugins/push-notify/windows/push-notify-handler.ps1`

## Events Our Plugin Handles

| Event | Type | Purpose |
|-------|------|---------|
| Completion | `event: session.idle` | Task finished (350ms delay) |
| Error | `event: session.error` | Error occurred (skip MessageAbortedError) |
| Permission | `event: permission.asked` | Approval needed |
| Question | `hook: tool.execute.before` (tool=question) | User input needed |

## Plugin Hook Signatures

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
