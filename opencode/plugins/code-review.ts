import type { Plugin } from "@opencode-ai/plugin"

export const CodeReview: Plugin = async () => {
  return {
    commands: {
      review: {
        description: "Analyze code quality, modularity, and identify refactoring opportunities",
        run: async ({ prompt }) => {
          const file = prompt.trim() || "@this"
          return {
            input: `Read through ${file} and analyze the code quality. Evaluate:

1. **Modularity** - Is the code well-organized into logical units? Are responsibilities clearly separated?
2. **Readability** - Is the code self-documenting? Are names descriptive and conventions consistent?
3. **Maintainability** - How easy would it be to modify or extend this code?
4. **Dead/Legacy Code** - Identify any unused imports, unreachable code paths, deprecated patterns, or logic that should be cleaned up.
5. **Error Handling** - Are edge cases and errors handled appropriately?

Summarize the impact of potential refactor options, prioritized by effort vs. benefit.`,
          }
        },
      },
    },
  }
}
