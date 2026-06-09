/** @jsxImportSource @opentui/solid */

import type { TuiPlugin } from "@opencode-ai/plugin/tui"

const PERPETUAL_DURATION = 999_999_999
const CLEAR_DURATION = 1
const COMMIT_AUDITOR_TITLE_PREFIX = "[git-hook:commit-msg]"

export const SubagentBanner: TuiPlugin = async (api) => {
  const running = new Map<string, { agent: string; title: string }>()

  const renderBanner = () => {
    if (running.size === 0) {
      api.ui.toast({ variant: "info", message: "", duration: CLEAR_DURATION })
      return
    }
    const entries = Array.from(running.values())
    const message =
      entries.length === 1 ? `${entries[0].agent}: ${entries[0].title}` : `${entries.length} subagents running`
    api.ui.toast({ variant: "info", title: "Subagent", message, duration: PERPETUAL_DURATION })
  }

  const remove = (sessionID: string) => {
    if (!running.delete(sessionID)) return
    renderBanner()
  }

  const offCreated = api.event.on("session.created", (event) => {
    const info = event.properties.info
    if (!info.parentID) return
    if (!info.title?.startsWith(COMMIT_AUDITOR_TITLE_PREFIX)) return
    running.set(event.properties.sessionID, { agent: "commit-auditor", title: info.title })
    renderBanner()
  })

  const offIdle = api.event.on("session.idle", (event) => remove(event.properties.sessionID))
  const offDeleted = api.event.on("session.deleted", (event) => remove(event.properties.sessionID))

  api.lifecycle.onDispose(() => {
    offCreated()
    offIdle()
    offDeleted()
  })
}

export default { id: "subagent-banner", tui: SubagentBanner }
