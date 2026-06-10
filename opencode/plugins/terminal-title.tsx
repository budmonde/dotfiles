/** @jsxImportSource @opentui/solid */

import type { TuiPlugin } from "@opencode-ai/plugin/tui"
import { createEffect } from "solid-js"

const PREFIX = "OC"
const MAX_LEN = 80

const basename = (path: string | undefined): string => {
  if (!path) return ""
  const normalized = path.replace(/\\/g, "/").replace(/\/+$/, "")
  const idx = normalized.lastIndexOf("/")
  return idx >= 0 ? normalized.slice(idx + 1) : normalized
}

const truncate = (s: string, max: number): string =>
  s.length > max ? s.slice(0, max - 3) + "..." : s

export const TerminalTitle: TuiPlugin = async (api) => {
  createEffect(() => {
    const route = api.route.current
    const path = api.state.path
    const cwd = basename(path.directory || path.worktree)
    const branch = api.state.vcs?.branch

    const segments: string[] = [PREFIX]

    let location = cwd || "?"
    if (branch) location += ` : ${branch}`
    segments.push(location)

    if (route.name === "session" && route.params?.sessionID) {
      const session = api.state.session.get(route.params.sessionID as string)
      if (session?.title) segments.push(session.title)
    } else if (route.name !== "home") {
      segments.push(route.name)
    }

    const title = truncate(segments.join(" | "), MAX_LEN)
    api.renderer.setTerminalTitle(title)
  })
}

export default { id: "terminal-title", tui: TerminalTitle }
