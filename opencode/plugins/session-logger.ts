import type { Plugin } from "@opencode-ai/plugin"
import { mkdirSync, appendFileSync, renameSync, existsSync, readFileSync, readdirSync } from "fs"
import { homedir } from "os"
import { join } from "path"

const LOGS_ROOT = join(homedir(), ".local", "share", "opencode", "logs")

function sanitizePath(path: string): string {
  return path
    .replace(/^\//, "")
    .replace(/\//g, "-")
}

function sanitizeTitle(title: string): string {
  return title
    .toLowerCase()
    .replace(/[~"'`]/g, "")
    .replace(/\s+/g, "-")
    .replace(/[^a-z0-9-]/g, "")
    .replace(/-+/g, "-")
    .replace(/^-|-$/g, "")
}

function getLogFilename(sessionId: string, title: string | undefined): string {
  const sanitizedTitle = title ? sanitizeTitle(title) : "untitled"
  return `${sessionId}-${sanitizedTitle}.jsonl`
}

function loadLoggedMessageIds(logPath: string): Set<string> {
  const logged = new Set<string>()
  if (!existsSync(logPath)) return logged

  try {
    const content = readFileSync(logPath, "utf-8")
    for (const line of content.split("\n")) {
      if (!line.trim()) continue
      const entry = JSON.parse(line)
      if (entry.type === "message" && entry.messageId) {
        logged.add(entry.messageId)
      }
    }
  } catch {
    // Ignore parse errors
  }
  return logged
}

export const SessionLogger: Plugin = async ({ client, directory }) => {
  const projectDir = join(LOGS_ROOT, sanitizePath(directory))
  mkdirSync(projectDir, { recursive: true })

  const sessionFiles = new Map<string, string>()
  const sessionTitles = new Map<string, string>()
  const loggedMessages = new Map<string, Set<string>>()
  const pendingMessages = new Map<string, Set<string>>()

  function getLogPath(sessionId: string): string {
    const filename = sessionFiles.get(sessionId)
    if (filename) return join(projectDir, filename)

    const title = sessionTitles.get(sessionId)
    const newFilename = getLogFilename(sessionId, title)
    sessionFiles.set(sessionId, newFilename)
    return join(projectDir, newFilename)
  }

  function appendLog(sessionId: string, entry: object): void {
    const logPath = getLogPath(sessionId)
    const line = JSON.stringify({ ...entry, timestamp: new Date().toISOString() }) + "\n"
    appendFileSync(logPath, line)
  }

  async function ensureSessionTracked(sessionId: string): Promise<void> {
    if (sessionFiles.has(sessionId)) return

    const sessionResponse = await client.session.get({ path: { id: sessionId } })
    const session = sessionResponse.data
    const title = session?.title || ""

    sessionTitles.set(sessionId, title)
    const filename = getLogFilename(sessionId, title)
    sessionFiles.set(sessionId, filename)

    appendLog(sessionId, {
      type: "session",
      sessionId,
      title,
      projectPath: directory,
    })
  }

  return {
    event: async ({ event }) => {
      try {
        if (event.type === "session.created") {
          const props = event.properties as any
          const sessionId = props?.id
          if (!sessionId) return

          sessionTitles.set(sessionId, props?.title || "")
          const filename = getLogFilename(sessionId, props?.title)
          sessionFiles.set(sessionId, filename)

          appendLog(sessionId, {
            type: "session",
            sessionId,
            title: props?.title || "",
            projectPath: directory,
          })
        }

        if (event.type === "session.updated") {
          const props = event.properties as any
          const sessionId = props?.info?.id
          if (!sessionId) return

          await ensureSessionTracked(sessionId)

          const oldTitle = sessionTitles.get(sessionId)
          const newTitle = props?.info?.title

          if (newTitle && newTitle !== oldTitle) {
            sessionTitles.set(sessionId, newTitle)

            const oldFilename = sessionFiles.get(sessionId)
            const newFilename = getLogFilename(sessionId, newTitle)

            if (oldFilename && oldFilename !== newFilename) {
              const oldPath = join(projectDir, oldFilename)
              const newPath = join(projectDir, newFilename)

              if (existsSync(oldPath)) {
                appendLog(sessionId, {
                  type: "rename",
                  oldTitle: oldTitle || "untitled",
                  newTitle,
                })

                renameSync(oldPath, newPath)
                sessionFiles.set(sessionId, newFilename)
              }
            }
          }
        }

        if (event.type === "message.updated") {
          const props = event.properties as any
          const sessionId = props?.info?.sessionID
          const messageId = props?.info?.id
          if (!sessionId || !messageId) return

          if (!pendingMessages.has(sessionId)) {
            pendingMessages.set(sessionId, new Set())
          }
          pendingMessages.get(sessionId)!.add(messageId)
        }

        if (event.type === "session.idle") {
          const props = event.properties as any
          const sessionId = props?.sessionID || props?.sessionId || props?.info?.id
          if (!sessionId) return

          await ensureSessionTracked(sessionId)

          if (!loggedMessages.has(sessionId)) {
            const logPath = getLogPath(sessionId)
            loggedMessages.set(sessionId, loadLoggedMessageIds(logPath))
          }
          const logged = loggedMessages.get(sessionId)!

          const messagesResponse = await client.session.messages({
            path: { id: sessionId },
          })

          const messages = messagesResponse.data
          if (!messages || messages.length === 0) return

          for (const msg of messages) {
            const messageId = msg.info?.id
            if (!messageId || logged.has(messageId)) continue

            appendLog(sessionId, {
              type: "message",
              messageId,
              role: msg.info?.role,
              parts: msg.parts,
            })

            logged.add(messageId)
          }

          pendingMessages.delete(sessionId)
        }

        if (event.type === "session.deleted") {
          const props = event.properties as any
          const sessionId = props?.id
          if (!sessionId) return

          appendLog(sessionId, { type: "deleted" })

          sessionFiles.delete(sessionId)
          sessionTitles.delete(sessionId)
          loggedMessages.delete(sessionId)
          pendingMessages.delete(sessionId)
        }
      } catch (error) {
        const message = error instanceof Error ? error.message : String(error)
        await client.tui.showToast({
          body: { message: `Session logger error: ${message}`, variant: "error" },
        })
      }
    },
  }
}
