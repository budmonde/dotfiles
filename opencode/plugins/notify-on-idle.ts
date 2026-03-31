import type { Plugin } from "@opencode-ai/plugin"

const DEBOUNCE_MS = 1000
const IDLE_DELAY_MS = 350

export const NotifyOnIdle: Plugin = async ({ $ }) => {
  const sessionTitles = new Map<string, string>()
  const lastNotifyTime = new Map<string, number>()
  const seenPermissions = new Set<string>()
  let pendingIdleTimeout: ReturnType<typeof setTimeout> | null = null
  let pendingIdleSessionId: string | null = null

  const opencodePaneId = process.env.TMUX_PANE || ""

  function shouldNotify(key: string): boolean {
    const now = Date.now()
    if (now - (lastNotifyTime.get(key) || 0) < DEBOUNCE_MS) return false
    lastNotifyTime.set(key, now)
    return true
  }

  function getSessionID(event: unknown): string | null {
    const props = (event as any)?.properties
    return props?.sessionID || props?.sessionId || props?.info?.id || null
  }

  async function sendNotification(title: string, message: string, sound?: string): Promise<void> {
    try {
      const args = []
      if (sound) {
        args.push("--sound", sound)
      }
      if (opencodePaneId) {
        args.push("--pane", opencodePaneId)
      }
      args.push(title, message)
      await $`push-notify ${args}`.quiet()
    } catch {
      // Ignore notification failures
    }
  }

  async function getNotificationContext(sessionId: string | null): Promise<{
    sessionTitle: string
    windowName: string
    shouldSend: boolean
  }> {
    const sessionTitle = (sessionId && sessionTitles.get(sessionId)) || "unknown"

    const paneTitle = await $`tmux display-message -t ${opencodePaneId} -p '#T' 2>/dev/null || true`.text()
    const activeTitleMatch = paneTitle.trim().match(/^OC \| (.+)$/)
    const activeSessionTitle = activeTitleMatch ? activeTitleMatch[1] : ""
    const isActiveSession = activeSessionTitle === sessionTitle

    const tmuxFocus = await $`tmux display-message -t ${opencodePaneId} -p '#{window_active}#{pane_active}' 2>/dev/null || echo "00"`.text()
    const isPaneFocused = tmuxFocus.trim() === "11"

    const tmuxWindow = await $`tmux display-message -t ${opencodePaneId} -p '#W' 2>/dev/null || true`.text()
    const windowName = tmuxWindow.trim() || "unknown"

    return {
      sessionTitle,
      windowName,
      shouldSend: !isActiveSession || !isPaneFocused,
    }
  }

  function cancelPendingIdle(): void {
    if (pendingIdleTimeout) {
      clearTimeout(pendingIdleTimeout)
      pendingIdleTimeout = null
      pendingIdleSessionId = null
    }
  }

  return {
    event: async ({ event }) => {
      if (event.type === "session.updated") {
        const props = event.properties as any
        if (props?.info?.id && props?.info?.title) {
          sessionTitles.set(props.info.id, props.info.title)
        }
      }

      if (event.type === "session.busy") {
        cancelPendingIdle()
      }

      if (event.type === "session.idle") {
        cancelPendingIdle()
        const sessionId = getSessionID(event)
        pendingIdleSessionId = sessionId

        pendingIdleTimeout = setTimeout(async () => {
          if (pendingIdleSessionId !== sessionId) return

          const key = `idle:${sessionId}`
          if (!shouldNotify(key)) return

          const ctx = await getNotificationContext(sessionId)
          if (ctx.shouldSend) {
            const message = `Session: ${ctx.sessionTitle}\nEvent: Task completed`
            await sendNotification(ctx.windowName, message)
          }
          pendingIdleTimeout = null
          pendingIdleSessionId = null
        }, IDLE_DELAY_MS)
      }

      if (event.type === "session.error") {
        const props = event.properties as any
        if (props?.error?.name === "MessageAbortedError") return

        const sessionId = getSessionID(event)
        const key = `error:${sessionId}`
        if (!shouldNotify(key)) return

        const ctx = await getNotificationContext(sessionId)
        if (ctx.shouldSend) {
          const errorMessage = props?.error?.message || "An error occurred"
          const truncated = errorMessage.length > 80 ? errorMessage.slice(0, 80) + "..." : errorMessage
          const message = `Session: ${ctx.sessionTitle}\nEvent: Error - ${truncated}`
          await sendNotification(ctx.windowName, message, "Windows Critical Stop")
        }
      }

      if (event.type === "permission.asked") {
        const props = event.properties as any
        const requestId = props?.id || props?.requestId
        if (requestId && seenPermissions.has(requestId)) return
        if (requestId) seenPermissions.add(requestId)

        const sessionId = getSessionID(event)
        const key = `permission:${sessionId}:${requestId || Date.now()}`
        if (!shouldNotify(key)) return

        const ctx = await getNotificationContext(sessionId)
        if (ctx.shouldSend) {
          const message = `Session: ${ctx.sessionTitle}\nEvent: Permission required`
          await sendNotification(ctx.windowName, message, "Windows Exclamation")
        }
      }
    },

    "tool.execute.before": async (input, output) => {
      try {
        const toolName = input.tool
        if (toolName !== "question") return

        const key = `question:${Date.now()}`
        if (!shouldNotify(key)) return

        const ctx = await getNotificationContext(null)
        if (ctx.shouldSend) {
          const message = `Session: ${ctx.sessionTitle}\nEvent: Input required`
          sendNotification(ctx.windowName, message, "Windows Exclamation")
        }
      } catch {
        // Ignore errors to avoid breaking the tool
      }
    },
  }
}
