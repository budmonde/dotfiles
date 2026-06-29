-- Avoids vim.ui_attach(ext_messages=true): that externalizes the cmdline UI
-- and would require re-implementing it (cf. noice.nvim).

local M = {}

local log_dir = vim.fn.stdpath("log")
local log_path = log_dir .. "/messages.log"
local max_bytes = 5 * 1024 * 1024
local uv = vim.uv or vim.loop

vim.fn.mkdir(log_dir, "p")

local level_names = {}
for name, value in pairs(vim.log.levels) do
    level_names[value] = name
end

local function rotate_if_needed()
    local stat = uv.fs_stat(log_path)
    if stat and stat.size > max_bytes then
        -- Windows rename fails if the destination exists.
        pcall(uv.fs_unlink, log_path .. ".1")
        pcall(uv.fs_rename, log_path, log_path .. ".1")
    end
end

local function write_entry(kind, text)
    rotate_if_needed()
    local f = io.open(log_path, "a")
    if not f then return end
    local single_line = tostring(text):gsub("\r\n", "\n"):gsub("\n", " | ")
    f:write(string.format("[%s] [%s] %s\n",
        os.date("%Y-%m-%dT%H:%M:%S"),
        kind,
        single_line))
    f:close()
end

local original_notify = vim.notify
vim.notify = function(msg, level, opts)
    local level_name = level_names[level] or "INFO"
    vim.schedule(function()
        pcall(write_entry, "notify." .. level_name, msg)
    end)
    return original_notify(msg, level, opts)
end

-- Catches what vim.notify misses: core errors, :echoerr, nvim_echo.
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

-- The API moved from vim.lsp.set_log_level to vim.lsp.log.set_level in nvim 0.11.
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
