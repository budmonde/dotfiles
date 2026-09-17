local M = {}

local aliases = {
    sl = true,
    sl1 = true,
    sl2 = true,
    sl3 = true,
    ssl = true,
    ssl1 = true,
    ssl2 = true,
    ssl3 = true,
    ["sl1-specific"] = true,
    ["sl2-specific"] = true,
    ["sl3-specific"] = true,
}

local highlights = {
    FugitiveSmartlogAbsoluteDate = "Aqua",
    FugitiveSmartlogArrow = "Yellow",
    FugitiveSmartlogAuthor = "Grey",
    FugitiveSmartlogCommittedDate = "Aqua",
    FugitiveSmartlogCommitter = "Grey",
    FugitiveSmartlogDecoration = "Yellow",
    FugitiveSmartlogGraph = "Grey",
    FugitiveSmartlogHash = "Blue",
    FugitiveSmartlogHead = "Aqua",
    FugitiveSmartlogLocal = "Green",
    FugitiveSmartlogRelativeDate = "Green",
    FugitiveSmartlogRemote = "Red",
    FugitiveSmartlogTag = "Yellow",
}

local function configure_syntax()
    local result = vim.fn.FugitiveResult(vim.api.nvim_get_current_buf())
    local alias = type(result) == "table" and result.args and result.args[1]
    if not aliases[alias] then
        return
    end

    vim.cmd([[
        syntax match FugitiveSmartlogGraph /^[*|\/\\ ]\+/
        syntax match FugitiveSmartlogHash /\<\x\{4,40\}\ze - /
        syntax region FugitiveSmartlogDecoration start=/\s(\ze[^()]*)\s*$/ end=/)$/ contains=FugitiveSmartlogLocal,FugitiveSmartlogRemote,FugitiveSmartlogTag,FugitiveSmartlogHead,FugitiveSmartlogArrow
        syntax match FugitiveSmartlogLocal /[[:alnum:]_.-]\+/ contained
        syntax match FugitiveSmartlogRemote /\<[[:alnum:]_.-]\+\/[[:alnum:]_.\/-]\+\>/ contained
        syntax match FugitiveSmartlogTag /tag: [^,)]*/ contained
        syntax keyword FugitiveSmartlogHead HEAD contained
        syntax match FugitiveSmartlogArrow /->/ contained
        syntax match FugitiveSmartlogRelativeDate /([^)]\+ ago)/ containedin=ALL
        syntax match FugitiveSmartlogCommittedDate /(committed: [^)]\+)/ containedin=ALL
        syntax match FugitiveSmartlogAuthor /- \zs\%(\%( - \)\@!.\)\{-}\ze\%(\s\+([^()]*)\)\?$/
        syntax match FugitiveSmartlogCommitter /(committer: [^)]\+)/ containedin=ALL
        syntax match FugitiveSmartlogAbsoluteDate /[A-Z][a-z]\{2}, \d\{1,2} [A-Z][a-z]\{2} \d\{4} \d\{2}:\d\{2}:\d\{2} [+-]\d\{4}/ containedin=ALL
    ]])

    for group, link in pairs(highlights) do
        vim.api.nvim_set_hl(0, group, { default = true, link = link })
    end
end

function M.setup(group)
    vim.api.nvim_create_autocmd("User", {
        group = group,
        pattern = "FugitivePager",
        callback = configure_syntax,
    })
end

return M
