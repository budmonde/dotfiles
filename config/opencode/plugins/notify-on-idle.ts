import type { Plugin } from "@opencode-ai/plugin"
import { basename } from "path"

const DEBOUNCE_MS = 1000
const IDLE_DELAY_MS = 350

export const NotifyOnIdle: Plugin = async ({ $ }) => {
  const sessionTitles = new Map<string, string>()
  const lastNotifyTime = new Map<string, number>()
  const seenPermissions = new Set<string>()
  let pendingIdleTimeout: ReturnType<typeof setTimeout> | null = null
  let pendingIdleSessionId: string | null = null

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
      args.push(title, message)
      await $`push-notify ${args}`.quiet()
    } catch {
      // Ignore notification failures
    }
  }

  async function getNotificationTitle(): Promise<string> {
    const dirName = basename(process.cwd())
    try {
      const ref = await $`git symbolic-ref --short HEAD`.quiet().text()
      const branch = ref.trim()
      if (branch) return `${dirName} : ${branch}`
    } catch {
      try {
        const rev = await $`git rev-parse --short HEAD`.quiet().text()
        if (rev.trim()) return `${dirName} : ${rev.trim()}`
      } catch {}
    }
    return dirName
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

          const sessionTitle = (sessionId && sessionTitles.get(sessionId)) || "unknown"
          const title = await getNotificationTitle()
          const message = `Session: ${sessionTitle}\nEvent: Task completed`
          await sendNotification(title, message)
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

        const sessionTitle = (sessionId && sessionTitles.get(sessionId)) || "unknown"
        const title = await getNotificationTitle()
        const errorMessage = props?.error?.message || "An error occurred"
        const truncated = errorMessage.length > 80 ? errorMessage.slice(0, 80) + "..." : errorMessage
        const message = `Session: ${sessionTitle}\nEvent: Error - ${truncated}`
        await sendNotification(title, message, "Windows Critical Stop")
      }

      if (event.type === "permission.asked") {
        const props = event.properties as any
        const requestId = props?.id || props?.requestId
        if (requestId && seenPermissions.has(requestId)) return
        if (requestId) seenPermissions.add(requestId)

        const sessionId = getSessionID(event)
        const key = `permission:${sessionId}:${requestId || Date.now()}`
        if (!shouldNotify(key)) return

        const sessionTitle = (sessionId && sessionTitles.get(sessionId)) || "unknown"
        const title = await getNotificationTitle()
        const message = `Session: ${sessionTitle}\nEvent: Permission required`
        await sendNotification(title, message, "Windows Exclamation")
      }
    },

    "tool.execute.before": async (input, output) => {
      try {
        const toolName = input.tool
        if (toolName !== "question") return

        const key = `question:${Date.now()}`
        if (!shouldNotify(key)) return

        const title = await getNotificationTitle()
        const message = `Event: Input required`
        sendNotification(title, message, "Windows Exclamation")
      } catch {
        // Ignore errors to avoid breaking the tool
      }
    },
  }
}
