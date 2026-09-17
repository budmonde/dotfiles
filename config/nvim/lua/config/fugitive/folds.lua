local M = {}

local function scan_fold(lines)
    local metadata = {
        file_highlight = "Folded",
    }
    for _, line in ipairs(lines) do
        local from = line:match("^rename from (.+)$")
        local to = line:match("^rename to (.+)$")
        if from then
            metadata.rename = metadata.rename or {}
            metadata.rename.from = vim.fn["fugitive#Unquote"](from)
        elseif to then
            metadata.rename = metadata.rename or {}
            metadata.rename.to = vim.fn["fugitive#Unquote"](to)
        end
        if line:match("^deleted file mode ") or line == "+++ /dev/null" then
            metadata.file_highlight = "Removed"
        elseif line:match("^new file mode ") or line == "--- /dev/null" then
            metadata.file_highlight = "Added"
        end
    end
    return metadata
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
    local prefix, additions, separator, deletions, filename_separator, filename =
        summary:match("^(%+%-+%s+)(%s*%d+%+)(%s+)(%s*%d+%-)(%s+)(.*)$")
    if not prefix then
        return nil
    end
    return {
        prefix = prefix,
        additions = {
            text = additions,
            count = tonumber(additions:match("%d+")),
        },
        separator = separator,
        deletions = {
            text = deletions,
            count = tonumber(deletions:match("%d+")),
        },
        filename_separator = filename_separator,
        filename = filename,
    }
end

local function diff_header_filename(line)
    local filename = vim.fn.matchstr(
        line,
        [[\C^diff .\{-\} \zs"\=[abciow12]/\zs.*\ze "\=[abciow12]/]]
    )
    if filename:sub(-1) == '"' then
        return vim.fn["fugitive#Unquote"]('"' .. filename)
    end
    return filename
end

local function complete_rename(metadata)
    local rename = metadata.rename
    if rename and rename.from and rename.to then
        return rename
    end
end

local function render_rename(prefix_chunks, spacing, rename)
    return vim.list_extend(prefix_chunks, rename_chunks(spacing, rename.from, rename.to))
end

local function render_binary(binary_prefix, binary_filename, lines, metadata, rename)
    if rename then
        return render_rename({ { binary_prefix, "Folded" } }, nil, rename)
    end
    local header_filename = diff_header_filename(lines[1])
    if header_filename ~= "" then
        binary_filename = header_filename
    end
    return {
        { binary_prefix, "Folded" },
        { binary_filename, metadata.file_highlight },
    }
end

local function render_summary(summary, metadata, rename)
    local chunks = {
        { summary.prefix, "Folded" },
        {
            summary.additions.text,
            summary.additions.count > 0 and "Added" or "Folded",
        },
        { summary.separator, "Folded" },
        {
            summary.deletions.text,
            summary.deletions.count > 0 and "Removed" or "Folded",
        },
    }
    if rename then
        return render_rename(chunks, summary.filename_separator, rename)
    end
    table.insert(chunks, { summary.filename_separator, "Folded" })
    table.insert(chunks, { summary.filename, metadata.file_highlight })
    return chunks
end

function M.foldtext()
    local summary = vim.fn["fugitive#Foldtext"]()
    local lines = vim.fn.getline(vim.v.foldstart, vim.v.foldend)
    local metadata = scan_fold(lines)
    local rename = complete_rename(metadata)
    local parsed_summary = parse_summary(summary)
    if parsed_summary then
        return render_summary(parsed_summary, metadata, rename)
    end

    local binary_prefix, binary_filename = summary:match("^(Binary:%s+)(.*)$")
    if binary_prefix then
        return render_binary(binary_prefix, binary_filename, lines, metadata, rename)
    end

    if rename then
        return render_rename(
            { { "+-" .. vim.v.folddashes .. " ", "Folded" } },
            nil,
            rename
        )
    end

    return { { summary, "Folded" } }
end

function M.setup(group)
    vim.cmd("highlight default link Renamed Yellow")
    vim.api.nvim_create_autocmd("User", {
        group = group,
        pattern = "FugitiveCommit",
        callback = function()
            vim.wo.foldmethod = "syntax"
            vim.wo.foldtext = "v:lua.require'config.fugitive'.foldtext()"
        end,
    })
end

return M
