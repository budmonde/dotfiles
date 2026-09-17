local script_path = debug.getinfo(1, "S").source:sub(2)
local nvim_root = vim.fs.dirname(vim.fs.dirname(script_path))
local fugitive_root = vim.fs.joinpath(vim.fn.stdpath("data"), "lazy", "vim-fugitive")

assert(vim.uv.fs_stat(fugitive_root), "vim-fugitive is not installed at " .. fugitive_root)

vim.opt.runtimepath:prepend(nvim_root)
vim.opt.runtimepath:prepend(fugitive_root)
vim.cmd.runtime("plugin/fugitive.vim")

local fugitive = require("config.fugitive")
fugitive.init()
fugitive.setup()

local configured_foldtext = _G.DotfilesFugitiveFoldtext
local captured_chunks

_G.DotfilesFugitiveFoldtext = function()
    captured_chunks = configured_foldtext()
    return captured_chunks
end

local function fold(lines)
    captured_chunks = nil
    vim.bo.modifiable = true
    vim.api.nvim_buf_set_lines(0, 0, -1, false, vim.list_extend(vim.deepcopy(lines), { "END" }))
    vim.bo.filetype = "git"
    vim.wo.foldmethod = "syntax"
    vim.wo.foldtext = "v:lua.DotfilesFugitiveFoldtext()"
    vim.cmd("silent! syntax clear DotfilesFugitiveTestDiff")
    vim.cmd("syntax region DotfilesFugitiveTestDiff start=/^diff / end=/^END$/ fold keepend")
    vim.wo.foldlevel = 0
    local rendered = vim.fn.foldtextresult(1)
    assert(captured_chunks, "fold text was not evaluated")
    return rendered, captured_chunks
end

local function assert_equal(actual, expected)
    assert(vim.deep_equal(actual, expected), ("expected:\n%s\nactual:\n%s"):format(
        vim.inspect(expected),
        vim.inspect(actual)
    ))
end

local function assert_contains(value, expected)
    assert(value:find(expected, 1, true), ("expected %q to contain %q"):format(value, expected))
end

local function test_modified_file()
    local rendered, chunks = fold({
        "diff --git a/lua/config.lua b/lua/config.lua",
        "index 1111111..2222222 100644",
        "--- a/lua/config.lua",
        "+++ b/lua/config.lua",
        "@@ -1 +1 @@",
        "-old",
        "+new",
    })

    assert_equal(rendered, "+--  1+  1- lua/config.lua")
    assert_equal(chunks[#chunks - 1], { " ", "Folded" })
    assert_equal(chunks[#chunks], { "lua/config.lua", "Folded" })
end

local function test_added_file()
    local rendered, chunks = fold({
        "diff --git a/lua/new.lua b/lua/new.lua",
        "new file mode 100644",
        "--- /dev/null",
        "+++ b/lua/new.lua",
        "@@ -0,0 +1 @@",
        "+new",
    })

    assert_equal(rendered, "+--  1+  0- lua/new.lua")
    assert_equal(chunks[#chunks - 1], { " ", "Folded" })
    assert_equal(chunks[#chunks], { "lua/new.lua", "Added" })
end

local function test_deleted_file()
    local rendered, chunks = fold({
        "diff --git a/lua/old.lua b/lua/old.lua",
        "deleted file mode 100644",
        "--- a/lua/old.lua",
        "+++ /dev/null",
        "@@ -1 +0,0 @@",
        "-old",
    })

    assert_equal(rendered, "+--  0+  1- lua/old.lua")
    assert_equal(chunks[#chunks - 1], { " ", "Folded" })
    assert_equal(chunks[#chunks], { "lua/old.lua", "Removed" })
end

local function test_binary_file()
    local rendered, chunks = fold({
        "diff --git a/assets/image.bin b/assets/image.bin",
        "index 1111111..2222222 100644",
        "Binary files a/assets/image.bin and b/assets/image.bin differ",
    })

    assert_equal(rendered, "Binary: sets/image.bin")
    assert_equal(chunks, {
        { "Binary: ", "Folded" },
        { "sets/image.bin", "Folded" },
    })
end

local function test_pure_rename_with_common_prefix()
    local rendered, chunks = fold({
        "diff --git a/install/lib/python/lifecycle.py b/install/lib/python/lifecycle/npm.py",
        "similarity index 100%",
        "rename from install/lib/python/lifecycle.py",
        "rename to install/lib/python/lifecycle/npm.py",
    })

    assert_equal(rendered, "+-- install/lib/python/{lifecycle.py → lifecycle/npm.py}")
    assert_equal(chunks, {
        { "+-- ", "Folded" },
        { "install/lib/python/", "Folded" },
        { "{", "Folded" },
        { "lifecycle.py", "Renamed" },
        { " → ", "Folded" },
        { "lifecycle/npm.py", "Renamed" },
        { "}", "Folded" },
    })
    assert_equal(vim.api.nvim_get_hl(0, { name = "Renamed", link = true }).link, "Yellow")
end

local function test_edited_rename_preserves_counts_and_spacing()
    local lines = {
        "diff --git a/install/lib/python/lifecycle.py b/install/lib/python/lifecycle/npm.py",
        "similarity index 50%",
        "rename from install/lib/python/lifecycle.py",
        "rename to install/lib/python/lifecycle/npm.py",
        "--- a/install/lib/python/lifecycle.py",
        "+++ b/install/lib/python/lifecycle/npm.py",
    }
    for _ = 1, 76 do
        table.insert(lines, "-old")
    end
    for _ = 1, 11 do
        table.insert(lines, "+new")
    end

    local rendered = fold(lines)
    assert_equal(rendered, "+-- 11+ 76- install/lib/python/{lifecycle.py → lifecycle/npm.py}")
end

local function test_rename_without_common_prefix()
    local rendered, chunks = fold({
        "diff --git a/old.lua b/new.lua",
        "similarity index 100%",
        "rename from old.lua",
        "rename to new.lua",
    })

    assert_equal(rendered, "+-- old.lua → new.lua")
    assert_equal(chunks, {
        { "+-- ", "Folded" },
        { "old.lua", "Renamed" },
        { " → ", "Folded" },
        { "new.lua", "Renamed" },
    })
end

local function test_spaces_and_quoted_paths()
    local rendered = fold({
        "diff --git \"a/docs/old name.txt\" \"b/docs/new name.txt\"",
        "similarity index 100%",
        "rename from \"docs/old name.txt\"",
        "rename to \"docs/new name.txt\"",
    })

    assert_contains(rendered, "docs/{old name.txt → new name.txt}")
end

local tests = {
    test_modified_file,
    test_added_file,
    test_deleted_file,
    test_binary_file,
    test_pure_rename_with_common_prefix,
    test_edited_rename_preserves_counts_and_spacing,
    test_rename_without_common_prefix,
    test_spaces_and_quoted_paths,
}

for _, test in ipairs(tests) do
    test()
end

print(("fugitive: %d tests passed"):format(#tests))
