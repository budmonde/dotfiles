import type { Plugin } from "@opencode-ai/plugin"

export const NotifyOnIdle: Plugin = async ({ $ }) => {
  const sessionTitles = new Map<string, string>()

  // Get the tmux pane ID where opencode is running (set at startup)
  const opencodePaneId = process.env.TMUX_PANE || ""

  return {
    event: async ({ event }) => {
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

        // Get tmux pane title for the opencode pane
        const paneTitle = await $`tmux display-message -t ${opencodePaneId} -p '#T' 2>/dev/null || true`.text()
        const activeTitleMatch = paneTitle.trim().match(/^OC \| (.+)$/)
        const activeSessionTitle = activeTitleMatch ? activeTitleMatch[1] : ""

        const isActiveSession = activeSessionTitle === sessionTitle

        // Check if the opencode pane/window is in focus
        const tmuxFocus = await $`tmux display-message -t ${opencodePaneId} -p '#{window_active}#{pane_active}' 2>/dev/null || echo "00"`.text()
        const isPaneFocused = tmuxFocus.trim() === "11"

        if (!isActiveSession || !isPaneFocused) {
          // Get the window name of the opencode pane (not current window)
          const tmuxWindow = await $`tmux display-message -t ${opencodePaneId} -p '#W' 2>/dev/null || true`.text()
          const windowName = tmuxWindow.trim() || "unknown"

          const title = `OpenCode - ${windowName}`
          const message = sessionTitle

          await $`notify ${title} ${message}`.quiet()
        }
      }
    },
  }
}
