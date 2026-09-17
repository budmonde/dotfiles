local folds = require("config.fugitive.folds")
local smartlog = require("config.fugitive.smartlog")

local M = {
    foldtext = folds.foldtext,
}

function M.init()
    vim.g.fugitive_focus_gained = 1
end

function M.setup()
    local group = vim.api.nvim_create_augroup("fugitive_customizations", { clear = true })
    folds.setup(group)
    smartlog.setup(group)
end

return M
