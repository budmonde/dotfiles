-- Telemetry: capture nvim messages (errors, warnings, notifications) into a
-- durable, XDG-compliant log for retroactive review.
--
-- Mechanisms (combined for coverage without disrupting nvim's UI):
--   1. vim.notify wrapper       - real-time capture of plugin-emitted messages.
--                                 Catches everything routed through vim.notify,
--                                 which is how most modern plugins surface
--                                 errors and warnings.
--   2. VimLeavePre :messages    - dumps the full message history at session
--                                 exit. Catches what (1) misses: core nvim
--                                 errors (E###), :echoerr, deprecation
--                                 warnings, and any direct nvim_echo calls.
--   3. vim.lsp.set_log_level    - ensures LSP-side warnings/errors persist in
--                                 the standard lsp.log alongside messages.log.
--
-- An earlier version used vim.ui_attach with ext_messages=true to tap msg_show
-- directly. That approach is a single chokepoint but it externalizes nvim's
-- message UI, which made the ':' cmdline prompt and message echo invisible.
-- Restoring that UI would require re-implementing the cmdline rendering
-- (which is what noice.nvim does). For a lightweight telemetry shim, the
-- notify-wrap + exit-dump combination is the right trade-off.
--
-- Log location: stdpath("log") which is XDG-compliant:
--   Linux/macOS: $XDG_STATE_HOME/nvim/log/  (default ~/.local/state/nvim/log/)
--   Windows:     ~/AppData/Local/nvim-data/
--
-- Review the log with :TelemetryShow, or grep it directly.

local M = {}

local log_dir = vim.fn.stdpath("log")
local log_path = log_dir .. "/messages.log"
local max_bytes = 5 * 1024 * 1024  -- 5 MB before rotation
local uv = vim.uv or vim.loop

-- Ensure log directory exists. stdpath("log") is usually pre-created by nvim,
-- but be defensive in case of fresh installs or non-standard layouts.
vim.fn.mkdir(log_dir, "p")

-- Reverse-lookup table for vim.log.levels integer -> name.
local level_names = {}
for name, value in pairs(vim.log.levels) do
    level_names[value] = name
end

local function rotate_if_needed()
    local stat = uv.fs_stat(log_path)
    if stat and stat.size > max_bytes then
        os.rename(log_path, log_path .. ".1")
    end
end

local function write_entry(kind, text)
    rotate_if_needed()
    local f = io.open(log_path, "a")
    if not f then return end
    -- Flatten embedded newlines to ' | ' so each log entry is one grep-friendly line.
    local single_line = tostring(text):gsub("\r\n", "\n"):gsub("\n", " | ")
    f:write(string.format("[%s] [%s] %s\n",
        os.date("%Y-%m-%dT%H:%M:%S"),
        kind,
        single_line))
    f:close()
end

-- (1) Wrap vim.notify to persist every notification in real time, then forward
-- to whatever notifier UI is currently installed (snacks.notifier, the default
-- nvim notifier, etc.). UI behavior is preserved.
local original_notify = vim.notify
vim.notify = function(msg, level, opts)
    local level_name = level_names[level] or "INFO"
    vim.schedule(function()
        pcall(write_entry, "notify." .. level_name, msg)
    end)
    return original_notify(msg, level, opts)
end

-- (2) On exit, dump the full :messages history with a session boundary. This
-- catches everything that didn't route through vim.notify: core nvim errors,
-- :echoerr calls, deprecation warnings, and direct nvim_echo emissions.
vim.api.nvim_create_autocmd("VimLeavePre", {
    group = vim.api.nvim_create_augroup("telemetry_messages_dump", { clear = true }),
    callback = function()
        local ok, messages = pcall(vim.api.nvim_exec2, "messages", { output = true })
        if not ok or not messages or not messages.output then return end
        local body = messages.output
        if body == "" then return end
        rotate_if_needed()
        local f = io.open(log_path, "a")
        if not f then return end
        f:write(string.format("[%s] [session_end] === :messages dump ===\n",
            os.date("%Y-%m-%dT%H:%M:%S")))
        for line in body:gmatch("[^\n]+") do
            f:write(string.format("[%s] [messages] %s\n",
                os.date("%Y-%m-%dT%H:%M:%S"), line))
        end
        f:write(string.format("[%s] [session_end] === end dump ===\n",
            os.date("%Y-%m-%dT%H:%M:%S")))
        f:close()
    end,
})

-- (3) Make sure LSP warnings/errors persist in the standard lsp.log. By
-- default the level is WARN, but setting it explicitly is cheap insurance
-- against future default changes. The API moved from vim.lsp.set_log_level to
-- vim.lsp.log.set_level in nvim 0.11; prefer the newer call and fall back.
local lsp_log_ok, lsp_log_mod = pcall(require, "vim.lsp.log")
if lsp_log_ok and lsp_log_mod and lsp_log_mod.set_level then
    pcall(lsp_log_mod.set_level, "WARN")
elseif vim.lsp and vim.lsp.set_log_level then
    pcall(vim.lsp.set_log_level, "WARN")
end

vim.api.nvim_create_user_command("TelemetryShow", function()
    vim.cmd("tabnew " .. vim.fn.fnameescape(log_path))
end, { desc = "Open the telemetry message log" })

vim.api.nvim_create_user_command("TelemetryPath", function()
    vim.api.nvim_echo({ { log_path } }, false, {})
end, { desc = "Print the telemetry log path" })

return M
