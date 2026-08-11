import type { Plugin } from "@opencode-ai/plugin"

const sessionAgent = new Map<string, string>()

export const OpencodeEnv: Plugin = async ({ serverUrl, directory }) => {
  return {
    "chat.params": async (input) => {
      if (input.sessionID && input.agent) {
        sessionAgent.set(input.sessionID, input.agent)
      }
    },
    "shell.env": async (input, output) => {
      output.env["OPENCODE_SERVER_URL"] = serverUrl.toString()
      output.env["OPENCODE_PROJECT_DIR"] = directory
      if (input.sessionID) {
        output.env["OPENCODE_SESSION_ID"] = input.sessionID
        const agent = sessionAgent.get(input.sessionID)
        if (agent) output.env["OPENCODE_SESSION_AGENT"] = agent
      }
      if (input.callID) output.env["OPENCODE_CALL_ID"] = input.callID
      if (process.env.OPENCODE_SERVER_USERNAME)
        output.env["OPENCODE_SERVER_USERNAME"] = process.env.OPENCODE_SERVER_USERNAME
      if (process.env.OPENCODE_SERVER_PASSWORD)
        output.env["OPENCODE_SERVER_PASSWORD"] = process.env.OPENCODE_SERVER_PASSWORD
    },
  }
}
