# OpenCode-specific agent guidance

<!-- opencode-marketplace:start -->
## Marketplace Skills (ocmp-* prefix)

Skills prefixed with `ocmp-` are imported from Claude Code plugin marketplaces
via opencode-marketplace. When using these skills:

- `${CLAUDE_PLUGIN_ROOT}`, `$CLAUDE_PLUGIN_ROOT`, and `{{PLUGIN_DIR}}` are path
  variables. Run `opencode-marketplace resolve <skill-name>` to get the actual
  paths for CLAUDE_PLUGIN_ROOT and CLAUDE_SKILL_DIR. The skill name is shown in
  the `<skill_content name="...">` tag when the skill is loaded.
- `${CLAUDE_SKILL_DIR}` refers to the directory containing the skill's SKILL.md.
  Also resolved by the `resolve` command.
- `!\`command\`` syntax (backtick preprocessing) means you should execute that
  command and use its output as context.
- `mcp__<server>__<tool>` references refer to MCP server tools. Match them to
  your configured MCP servers by name and function.
- `allowed-tools` in frontmatter is advisory — it indicates which tools the skill
  was designed to use, but is not enforced.
- `disable-model-invocation` and `user-invocable` are Claude Code flags preserved
  for documentation; they have no effect in OpenCode.
<!-- opencode-marketplace:end -->
