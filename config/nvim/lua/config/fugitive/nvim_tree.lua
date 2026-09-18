local M = {}

local nvim_tree_api = require("nvim-tree.api")
local nvim_tree_config = require("nvim-tree.config")

local function selected_git_dir()
    local node = nvim_tree_api.tree.get_node_under_cursor()
    local path = node and node.absolute_path
    local git_dir = path and vim.fn.FugitiveExtractGitDir(path) or ""
    if git_dir == "" then
        vim.notify("The selected nvim-tree node is not in a Git repository", vim.log.levels.WARN)
        return nil
    end
    return git_dir
end

local function run_with_git_dir(git_dir, command)
    local buffer = vim.api.nvim_get_current_buf()
    local previous_git_dir = vim.b[buffer].git_dir
    vim.b[buffer].git_dir = git_dir
    local ok, error_message = pcall(command)
    if vim.api.nvim_buf_is_valid(buffer) then
        vim.b[buffer].git_dir = previous_git_dir
    end
    if not ok then
        vim.notify(error_message, vim.log.levels.ERROR)
    end
end

local function usable_windows(tree_window)
    local exclusions = nvim_tree_config.g.actions.open_file.window_picker.exclude
    return vim.tbl_filter(function(window)
        local window_config = vim.api.nvim_win_get_config(window)
        if window == tree_window or window_config.relative ~= "" or not window_config.focusable then
            return false
        end

        local buffer = vim.api.nvim_win_get_buf(window)
        for option, excluded_values in pairs(exclusions) do
            local ok, value = pcall(vim.api.nvim_get_option_value, option, { buf = buffer })
            if ok and vim.tbl_contains(excluded_values, value) then
                return false
            end
        end
        return true
    end, vim.api.nvim_tabpage_list_wins(0))
end

local function restore_picker(saved_options, laststatus)
    for window, options in pairs(saved_options) do
        if vim.api.nvim_win_is_valid(window) then
            vim.api.nvim_set_option_value("statusline", options.statusline, { win = window })
            vim.api.nvim_set_option_value("winhl", options.winhl, { win = window })
        end
    end
    vim.o.laststatus = laststatus
    vim.api.nvim_echo({ { "" } }, false, {})
    vim.cmd("redraw")
end

local function pick_window(windows)
    local chars = nvim_tree_config.g.actions.open_file.window_picker.chars
    if #windows > #chars then
        vim.notify("Too many windows for the nvim-tree window picker", vim.log.levels.ERROR)
        return nil
    end

    local choices = {}
    local saved_options = {}
    local previous_laststatus = vim.o.laststatus
    vim.o.laststatus = 2

    for index, window in ipairs(windows) do
        local char = chars:sub(index, index)
        choices[char] = window
        saved_options[window] = {
            statusline = vim.api.nvim_get_option_value("statusline", { win = window }),
            winhl = vim.api.nvim_get_option_value("winhl", { win = window }),
        }
        vim.api.nvim_set_option_value("statusline", "%=" .. char .. "%=", { win = window })
        vim.api.nvim_set_option_value(
            "winhl",
            "StatusLine:NvimTreeWindowPicker,StatusLineNC:NvimTreeWindowPicker",
            { win = window }
        )
    end

    vim.cmd("redraw")
    vim.api.nvim_echo({ { "Pick window: " } }, false, {})
    local ok, response = pcall(vim.fn.getcharstr)
    restore_picker(saved_options, previous_laststatus)

    if not ok then
        return nil
    end
    return choices[response:upper()]
end

local function target_window(tree_window)
    local windows = usable_windows(tree_window)
    if #windows == 0 then
        vim.cmd("rightbelow vnew")
        return vim.api.nvim_get_current_win(), vim.api.nvim_get_current_buf()
    elseif #windows == 1 then
        return windows[1]
    end
    return pick_window(windows)
end

local function use_repository_context(window, git_dir, buffer)
    vim.api.nvim_set_current_win(window)
    buffer = buffer or vim.api.nvim_create_buf(false, false)
    vim.bo[buffer].bufhidden = "wipe"
    vim.b[buffer].git_dir = git_dir
    vim.api.nvim_win_set_buf(window, buffer)
end

local function open_selected_view(split_command, curwin_command)
    local git_dir = selected_git_dir()
    if not git_dir then
        return
    end

    local window, context_buffer = target_window(vim.api.nvim_get_current_win())
    if not window then
        return
    end

    if context_buffer then
        use_repository_context(window, git_dir, context_buffer)
        run_with_git_dir(git_dir, function()
            vim.cmd(curwin_command)
        end)
    else
        vim.api.nvim_set_current_win(window)
        run_with_git_dir(git_dir, function()
            vim.cmd(split_command)
        end)
    end
end

function M.open_selected_status()
    open_selected_view("belowright Git", "Git ++curwin")
end

function M.open_selected_smartlog()
    open_selected_view("belowright Git -p sl", "Git ++curwin -p sl")
end

function M.open_selected_log()
    local git_dir = selected_git_dir()
    if not git_dir then
        return
    end

    local tree_window = vim.api.nvim_get_current_win()
    local window, context_buffer = target_window(tree_window)
    if not window then
        return
    end

    use_repository_context(window, git_dir, context_buffer)

    local ok, error_message = pcall(vim.cmd, "Gclog --all")
    if not ok then
        vim.notify(error_message, vim.log.levels.ERROR)
    end
end

return M
