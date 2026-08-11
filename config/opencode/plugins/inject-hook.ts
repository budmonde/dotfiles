import type { Plugin } from "@opencode-ai/plugin"
import { appendFileSync, existsSync, readFileSync } from "fs"
import { homedir } from "os"
import { join } from "path"

const SIDECAR_RELPATH = ".opencode/inject-hooks.json"

const dataHome = process.env.XDG_DATA_HOME || join(homedir(), ".local", "share")
const DEBUG_LOG = join(dataHome, "opencode", "inject-hook-debug.log")

type HookDefinition = {
  name: string
  tool: string
  match_arg: string
  pattern: string
  pattern_flags?: string
  message_template: string
  enabled?: boolean
}

type SidecarConfig = {
  debug?: boolean
  hooks?: HookDefinition[]
}

type CompiledHook = {
  def: HookDefinition
  matcher: RegExp
}

function loadSidecar(projectDir: string): SidecarConfig | null {
  const path = join(projectDir, SIDECAR_RELPATH)
  if (!existsSync(path)) return null
  try {
    return JSON.parse(readFileSync(path, "utf8")) as SidecarConfig
  } catch {
    return null
  }
}

function makeDebug(enabled: boolean) {
  return (msg: string) => {
    if (!enabled) return
    try {
      appendFileSync(DEBUG_LOG, `${new Date().toISOString()} ${msg}\n`)
    } catch {
      // ignore
    }
  }
}

function compileHooks(config: SidecarConfig | null): CompiledHook[] {
  if (!config?.hooks) return []
  const out: CompiledHook[] = []
  for (const def of config.hooks) {
    if (def.enabled === false) continue
    try {
      out.push({
        def,
        matcher: new RegExp(def.pattern, def.pattern_flags ?? ""),
      })
    } catch {
      // skip hooks with invalid regex
    }
  }
  return out
}

type SDKClient = {
  session: {
    prompt: (opts: {
      path: { id: string }
      body?: {
        noReply?: boolean
        parts: Array<{ type: "text"; text: string }>
      }
    }) => Promise<{
      response?: { status?: number }
    }>
  }
}

function renderTemplate(template: string, vars: Record<string, string>): string {
  return template.replace(/\{\{(\w+)\}\}/g, (_match, key) =>
    Object.prototype.hasOwnProperty.call(vars, key) ? vars[key] : `{{${key}}}`,
  )
}

type PendingInjection = {
  hookName: string
  message: string
}

export const InjectHook: Plugin = async ({ client, directory }) => {
  const pending = new Map<string, PendingInjection[]>()

  return {
    "tool.execute.before": async (input, output) => {
      const config = loadSidecar(directory)
      if (!config) return

      const debug = makeDebug(config.debug === true)
      const hooks = compileHooks(config)
      if (hooks.length === 0) return

      const args = (output.args ?? {}) as Record<string, unknown>
      const candidates = hooks.filter((h) => h.def.tool === input.tool)
      if (candidates.length === 0) return

      const injections: PendingInjection[] = []
      const matchedNames: string[] = []
      for (const hook of candidates) {
        const rawValue = args[hook.def.match_arg]
        if (rawValue === undefined || rawValue === null) continue
        const value = typeof rawValue === "string" ? rawValue : JSON.stringify(rawValue)
        if (!hook.matcher.test(value)) continue

        const message = renderTemplate(hook.def.message_template, {
          hook: hook.def.name,
          tool: input.tool,
          match: value,
          cwd: process.cwd(),
        })
        injections.push({ hookName: hook.def.name, message })
        matchedNames.push(hook.def.name)
      }
      if (injections.length === 0) return

      debug(`[${input.callID}] matched ${injections.length} hook(s): ${matchedNames.join(", ")}`)
      pending.set(input.callID, injections)
    },

    "tool.execute.after": async (input, _output) => {
      const config = loadSidecar(directory)
      if (!config) return

      const debug = makeDebug(config.debug === true)
      const injections = pending.get(input.callID)
      if (!injections) return
      pending.delete(input.callID)

      const sessionID = input.sessionID
      if (!sessionID) {
        debug(`[${input.callID}] no sessionID, cannot post hook messages`)
        return
      }

      for (const injection of injections) {
        try {
          const result = await (client as SDKClient).session.prompt({
            path: { id: sessionID },
            body: {
              noReply: true,
              parts: [{ type: "text", text: injection.message }],
            },
          })
          const status = result?.response?.status
          debug(`[${input.callID}] hook=${injection.hookName} posted status=${status}`)
        } catch (err) {
          debug(
            `[${input.callID}] hook=${injection.hookName} session.prompt ERROR: ${(err as Error).message}`,
          )
        }
      }
    },
  }
}
