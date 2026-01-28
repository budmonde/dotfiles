import type { Plugin } from "@opencode-ai/plugin"

export const NotifyOnIdle: Plugin = async ({ $ }) => {
  // Track session info from session.updated events (per session ID)
  const sessionTitles = new Map<string, string>()

  return {
    event: async ({ event }) => {
      // Capture session title from session.updated events
      // Structure: event.properties.info.id, event.properties.info.title
      if (event.type === "session.updated") {
        const props = event.properties as any
        if (props?.info?.id && props?.info?.title) {
          sessionTitles.set(props.info.id, props.info.title)
        }
      }

      if (event.type === "session.idle") {
        const props = event.properties as any
        const sessionId = props?.sessionID || props?.sessionId || props?.info?.id
        const sessionTitle = sessionTitles.get(sessionId) || "unknown"

        // Get tmux pane title - format is "OC | {session title}"
        const paneTitle = await $`tmux display-message -p '#T' 2>/dev/null || true`.text()
        const activeTitleMatch = paneTitle.trim().match(/^OC \| (.+)$/)
        const activeSessionTitle = activeTitleMatch ? activeTitleMatch[1] : ""

        // Check if this session is the active one in the TUI
        const isActiveSession = activeSessionTitle === sessionTitle

        // Check if tmux pane/window is in focus
        const tmuxFocus = await $`tmux display-message -p '#{window_active}#{pane_active}' 2>/dev/null || echo "00"`.text()
        const isPaneFocused = tmuxFocus.trim() === "11"

        // Only notify if:
        // 1. The session is not the active one in opencode TUI, OR
        // 2. The tmux pane/window is not in focus
        if (!isActiveSession || !isPaneFocused) {
          // Get tmux window name
          const tmuxWindow = await $`tmux display-message -p '#W' 2>/dev/null || true`.text()
          const windowName = tmuxWindow.trim() || "unknown"

          // Build notification
          const title = `OpenCode - ${windowName}`
          const message = sessionTitle

          // Send notification using cross-platform notify script
          await $`notify ${title} ${message}`.quiet()
        }
      }
    },
  }
}
