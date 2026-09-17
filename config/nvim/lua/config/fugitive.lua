local M = {}

local smartlog_aliases = {
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

local function configure_smartlog_syntax()
    local result = vim.fn.FugitiveResult(vim.api.nvim_get_current_buf())
    local alias = type(result) == "table" and result.args and result.args[1]
    if not smartlog_aliases[alias] then
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

    vim.cmd("highlight default link FugitiveSmartlogGraph Grey")
    vim.cmd("highlight default link FugitiveSmartlogHash Blue")
    vim.cmd("highlight default link FugitiveSmartlogAbsoluteDate Aqua")
    vim.cmd("highlight default link FugitiveSmartlogRelativeDate Green")
    vim.cmd("highlight default link FugitiveSmartlogCommittedDate Aqua")
    vim.cmd("highlight default link FugitiveSmartlogAuthor Grey")
    vim.cmd("highlight default link FugitiveSmartlogCommitter Grey")
    vim.cmd("highlight default link FugitiveSmartlogDecoration Yellow")
    vim.cmd("highlight default link FugitiveSmartlogLocal Green")
    vim.cmd("highlight default link FugitiveSmartlogRemote Red")
    vim.cmd("highlight default link FugitiveSmartlogTag Yellow")
    vim.cmd("highlight default link FugitiveSmartlogHead Aqua")
    vim.cmd("highlight default link FugitiveSmartlogArrow Yellow")
end

local function scan_fold(lines)
    local file_highlight = "Folded"
    local rename_from
    local rename_to
    for _, line in ipairs(lines) do
        local from = line:match("^rename from (.+)$")
        local to = line:match("^rename to (.+)$")
        if from then
            rename_from = vim.fn["fugitive#Unquote"](from)
        elseif to then
            rename_to = vim.fn["fugitive#Unquote"](to)
        end
        if line:match("^deleted file mode ") or line == "+++ /dev/null" then
            file_highlight = "Removed"
        elseif line:match("^new file mode ") or line == "--- /dev/null" then
            file_highlight = "Added"
        end
    end
    return file_highlight, rename_from, rename_to
end

local function rename_chunks(spacing, rename_from, rename_to)
    local chunks = {}
    local from_parts = vim.split(rename_from, "/", { plain = true })
    local to_parts = vim.split(rename_to, "/", { plain = true })
    local common_parts = {}
    while #from_parts > 1 and #to_parts > 1 and from_parts[1] == to_parts[1] do
        table.insert(common_parts, table.remove(from_parts, 1))
        table.remove(to_parts, 1)
    end
    local common_prefix = #common_parts > 0 and table.concat(common_parts, "/") .. "/" or ""
    if spacing and spacing ~= "" then
        table.insert(chunks, { spacing, "Folded" })
    end
    if common_prefix ~= "" then
        table.insert(chunks, { common_prefix, "Folded" })
        table.insert(chunks, { "{", "Folded" })
    end
    vim.list_extend(chunks, {
        { table.concat(from_parts, "/"), "Renamed" },
        { " → ", "Folded" },
        { table.concat(to_parts, "/"), "Renamed" },
    })
    if common_prefix ~= "" then
        table.insert(chunks, { "}", "Folded" })
    end
    return chunks
end

local function parse_summary(summary)
    return summary:match("^(%+%-+%s+)(%s*%d+%+)(%s+)(%s*%d+%-)(%s+)(.*)$")
end

local function foldtext()
    local summary = vim.fn["fugitive#Foldtext"]()
    local lines = vim.fn.getline(vim.v.foldstart, vim.v.foldend)
    local file_highlight, rename_from, rename_to = scan_fold(lines)
    local prefix, additions, separator, deletions, filename_separator, filename = parse_summary(summary)

    if not prefix then
        local binary_prefix, binary_filename = summary:match("^(Binary:%s+)(.*)$")
        if binary_prefix then
            if rename_from and rename_to then
                return vim.list_extend(
                    { { binary_prefix, "Folded" } },
                    rename_chunks(nil, rename_from, rename_to)
                )
            end
            return {
                { binary_prefix, "Folded" },
                { binary_filename, file_highlight },
            }
        end
        if rename_from and rename_to then
            return vim.list_extend(
                { { "+-" .. vim.v.folddashes .. " ", "Folded" } },
                rename_chunks(nil, rename_from, rename_to)
            )
        end
        return { { summary, "Folded" } }
    end

    local chunks = {
        { prefix, "Folded" },
        { additions, tonumber(additions:match("%d+")) > 0 and "Added" or "Folded" },
        { separator, "Folded" },
        { deletions, tonumber(deletions:match("%d+")) > 0 and "Removed" or "Folded" },
    }
    if rename_from and rename_to then
        vim.list_extend(chunks, rename_chunks(filename_separator, rename_from, rename_to))
    else
        table.insert(chunks, { filename_separator, "Folded" })
        table.insert(chunks, { filename, file_highlight })
    end
    return chunks
end

function M.init()
    vim.g.fugitive_focus_gained = 1
end

function M.setup()
    local fugitive_group = vim.api.nvim_create_augroup("fugitive_customizations", { clear = true })

    vim.cmd("highlight default link Renamed Yellow")
    _G.DotfilesFugitiveFoldtext = foldtext

    vim.api.nvim_create_autocmd("User", {
        group = fugitive_group,
        pattern = "FugitiveCommit",
        callback = function()
            vim.wo.foldtext = "v:lua.DotfilesFugitiveFoldtext()"
        end,
    })

    vim.api.nvim_create_autocmd("User", {
        group = fugitive_group,
        pattern = "FugitivePager",
        callback = configure_smartlog_syntax,
    })
end

return M
