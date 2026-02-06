-------------------------------------------------------------------------------
-- Bootstrap lazy.nvim
-------------------------------------------------------------------------------
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.loop.fs_stat(lazypath) then
    vim.fn.system({
        "git",
        "clone",
        "--filter=blob:none",
        "https://github.com/folke/lazy.nvim.git",
        "--branch=stable",
        lazypath,
    })
end
vim.opt.rtp:prepend(lazypath)

-------------------------------------------------------------------------------
-------------------------------------------------------------------------------
------------------------------------------------- Appearance and Window Dynamics
-------------------------------------------------------------------------------
-------------------------------------------------------------------------------
local appearance_plugins = {
    ---------------------------------------------------------------------------
    --- PLUGIN : gruvbox-material
    ---------------------------------------------------------------------------
    {
        "sainnhe/gruvbox-material",
        lazy = false,
        priority = 1000,
        config = function()
            vim.g.gruvbox_material_foreground = "original"
            vim.g.gruvbox_material_better_performance = 1
            -- Disable italic comments if terminal doesn't support italics
            if vim.env.TERM and vim.env.TERM:match("^screen") then
                vim.g.gruvbox_material_disable_italic_comment = 1
            end
            vim.cmd.colorscheme("gruvbox-material")
        end,
    },

    ---------------------------------------------------------------------------
    --- PLUGIN : lualine.nvim (replaces vim-airline)
    ---------------------------------------------------------------------------
    {
        "nvim-lualine/lualine.nvim",
        dependencies = { "nvim-tree/nvim-web-devicons" },
        config = function()
            local use_nerd_fonts = vim.g.use_nerd_fonts ~= 0  -- default true
            require("lualine").setup({
                options = {
                    theme = "gruvbox-material",
                    icons_enabled = use_nerd_fonts,
                    section_separators = use_nerd_fonts and { left = '', right = '' } or { left = '', right = '' },
                    component_separators = use_nerd_fonts and { left = '', right = '' } or { left = '|', right = '|' },
                },
                extensions = { "nvim-tree", "fugitive" },
            })
        end,
    },

    ---------------------------------------------------------------------------
    --- PLUGIN : vim-tmux-navigator
    ---------------------------------------------------------------------------
    {
        "christoomey/vim-tmux-navigator",
        init = function()
            vim.g.tmux_navigator_no_mappings = 1
        end,
        config = function()
            vim.keymap.set("n", "<M-h>", ":TmuxNavigateLeft<CR>", { silent = true })
            vim.keymap.set("n", "<M-j>", ":TmuxNavigateDown<CR>", { silent = true })
            vim.keymap.set("n", "<M-k>", ":TmuxNavigateUp<CR>", { silent = true })
            vim.keymap.set("n", "<M-l>", ":TmuxNavigateRight<CR>", { silent = true })
            vim.keymap.set("n", "<M-\\>", ":TmuxNavigatePrevious<CR>", { silent = true })
        end,
    },

    ---------------------------------------------------------------------------
    --- PLUGIN : vim-better-whitespace
    ---------------------------------------------------------------------------
    {
        "ntpeters/vim-better-whitespace",
        init = function()
            vim.g.better_whitespace_enabled = 1
            vim.g.strip_whitespace_on_save = 1
            vim.g.better_whitespace_ctermcolor = "gray"
        end,
    },
}

-------------------------------------------------------------------------------
-------------------------------------------------------------------------------
------------------------------------------------ Filesystem, Buffers and Search
-------------------------------------------------------------------------------
-------------------------------------------------------------------------------
local filesystem_plugins = {
    ---------------------------------------------------------------------------
    --- PLUGIN : nvim-tree (replaces nerdtree)
    ---------------------------------------------------------------------------
    {
        "nvim-tree/nvim-tree.lua",
        dependencies = { "nvim-tree/nvim-web-devicons" },
        config = function()
            local use_nerd_fonts = vim.g.use_nerd_fonts ~= 0  -- default true
            require("nvim-tree").setup({
                view = { width = 60 },
                sync_root_with_cwd = true,
                respect_buf_cwd = true,
                update_focused_file = {
                    enable = true,
                    update_root = true,
                },
                actions = {
                    change_dir = { enable = true, global = false },
                },
                renderer = {
                    icons = {
                        show = {
                            file = use_nerd_fonts,
                            folder = true,
                            folder_arrow = true,
                            git = true,
                        },
                        glyphs = use_nerd_fonts and {} or {
                            folder = {
                                arrow_closed = ">",
                                arrow_open = "v",
                                default = "[D]",
                                open = "[O]",
                                empty = "[E]",
                                empty_open = "[E]",
                                symlink = "[L]",
                                symlink_open = "[L]",
                            },
                            git = {
                                unstaged = "M",
                                staged = "S",
                                unmerged = "!",
                                renamed = "R",
                                untracked = "?",
                                deleted = "D",
                                ignored = "-",
                            },
                        },
                    },
                },
            })
            vim.keymap.set("n", "<M-n>", ":NvimTreeToggle<CR>", { silent = true })
            vim.keymap.set("n", "<M-N>", ":NvimTreeFindFile<CR>", { silent = true })
        end,
    },

    ---------------------------------------------------------------------------
    --- PLUGIN : telescope.nvim (replaces fzf)
    ---------------------------------------------------------------------------
    {
        "nvim-telescope/telescope.nvim",
        dependencies = { "nvim-lua/plenary.nvim" },
        config = function()
            require("telescope").setup({
                defaults = {
                    mappings = {
                        i = {
                            ["<C-j>"] = "move_selection_next",
                            ["<C-k>"] = "move_selection_previous",
                        },
                    },
                },
            })
            local builtin = require("telescope.builtin")
            -- File finders
            vim.keymap.set("n", "<C-p>", builtin.find_files, { desc = "Find files" })
            vim.keymap.set("n", "<leader>p", builtin.git_files, { desc = "Git files" })
            vim.keymap.set("n", "<leader>b", builtin.buffers, { desc = "Buffers" })
            vim.keymap.set("n", "<leader>h", builtin.oldfiles, { desc = "Recent files" })
            -- Search content
            vim.keymap.set("n", "<leader>ag", builtin.grep_string, { desc = "Grep word under cursor" })
            vim.keymap.set("n", "<leader>/", builtin.live_grep, { desc = "Live grep" })
        end,
    },

    ---------------------------------------------------------------------------
    --- PLUGIN : gitsigns.nvim (replaces vim-gitgutter)
    ---------------------------------------------------------------------------
    {
        "lewis6991/gitsigns.nvim",
        config = function()
            require("gitsigns").setup()
        end,
    },

    ---------------------------------------------------------------------------
    --- PLUGIN : vim-fugitive
    ---------------------------------------------------------------------------
    { "tpope/vim-fugitive" },
}

-------------------------------------------------------------------------------
-------------------------------------------------------------------------------
------------------------------------------------------- Movement and Navigation
-------------------------------------------------------------------------------
-------------------------------------------------------------------------------
local movement_plugins = {
    ---------------------------------------------------------------------------
    --- PLUGIN : flash.nvim (replaces vim-easymotion)
    ---------------------------------------------------------------------------
    {
        "folke/flash.nvim",
        event = "VeryLazy",
        opts = {},
        keys = {
            { "<leader><leader>f", mode = { "n", "x", "o" }, function() require("flash").jump() end, desc = "Flash" },
            { "<leader><leader>w", mode = { "n", "x", "o" }, function() require("flash").treesitter() end, desc = "Flash Treesitter" },
        },
    },

    ---------------------------------------------------------------------------
    --- PLUGIN : nvim-surround (replaces vim-surround)
    ---------------------------------------------------------------------------
    {
        "kylechui/nvim-surround",
        version = "*",
        event = "VeryLazy",
        config = function()
            require("nvim-surround").setup()
        end,
    },
}

-------------------------------------------------------------------------------
-------------------------------------------------------------------------------
-------------------------------------------- Syntax, Auto-completion and Indent
-------------------------------------------------------------------------------
-------------------------------------------------------------------------------
local syntax_plugins = {
    ---------------------------------------------------------------------------
    --- PLUGIN : nvim-treesitter
    ---------------------------------------------------------------------------
    {
        "nvim-treesitter/nvim-treesitter",
        build = ":TSUpdate",
        config = function()
            -- Enable treesitter highlighting for supported filetypes
            vim.api.nvim_create_autocmd("FileType", {
                pattern = { "python", "lua", "vim", "bash", "json", "yaml", "markdown", "javascript", "typescript" },
                callback = function()
                    pcall(vim.treesitter.start)
                end,
            })
        end,
    },

    ---------------------------------------------------------------------------
    --- PLUGIN : mason.nvim (LSP/linter/formatter installer)
    ---------------------------------------------------------------------------
    {
        "williamboman/mason.nvim",
        config = function()
            require("mason").setup()
        end,
    },
    {
        "williamboman/mason-lspconfig.nvim",
        dependencies = { "williamboman/mason.nvim", "neovim/nvim-lspconfig" },
        config = function()
            require("mason-lspconfig").setup({
                ensure_installed = { "pyright", "lua_ls" },
            })
        end,
    },

    ---------------------------------------------------------------------------
    --- PLUGIN : nvim-lspconfig (replaces jedi-vim)
    ---------------------------------------------------------------------------
    {
        "neovim/nvim-lspconfig",
        dependencies = { "williamboman/mason-lspconfig.nvim" },
        config = function()
            local capabilities = require("cmp_nvim_lsp").default_capabilities()

            -- Python
            vim.lsp.config.pyright = {
                cmd = { "pyright-langserver", "--stdio" },
                filetypes = { "python" },
                root_markers = { "pyproject.toml", "setup.py", "setup.cfg", "requirements.txt", ".git" },
                capabilities = capabilities,
            }
            vim.lsp.enable("pyright")

            -- Lua
            vim.lsp.config.lua_ls = {
                cmd = { "lua-language-server" },
                filetypes = { "lua" },
                root_markers = { ".luarc.json", ".luarc.jsonc", ".git" },
                capabilities = capabilities,
                settings = {
                    Lua = {
                        diagnostics = { globals = { "vim" } },
                    },
                },
            }
            vim.lsp.enable("lua_ls")
        end,
    },

    ---------------------------------------------------------------------------
    --- PLUGIN : nvim-cmp (autocompletion)
    ---------------------------------------------------------------------------
    {
        "hrsh7th/nvim-cmp",
        dependencies = {
            "hrsh7th/cmp-nvim-lsp",
            "hrsh7th/cmp-buffer",
            "hrsh7th/cmp-path",
            "L3MON4D3/LuaSnip",
            "saadparwaiz1/cmp_luasnip",
        },
        config = function()
            local cmp = require("cmp")
            local luasnip = require("luasnip")

            cmp.setup({
                snippet = {
                    expand = function(args)
                        luasnip.lsp_expand(args.body)
                    end,
                },
                mapping = cmp.mapping.preset.insert({
                    ["<C-b>"] = cmp.mapping.scroll_docs(-4),
                    ["<C-f>"] = cmp.mapping.scroll_docs(4),
                    ["<C-Space>"] = cmp.mapping.complete(),
                    ["<C-e>"] = cmp.mapping.abort(),
                    ["<CR>"] = cmp.mapping.confirm({ select = true }),
                    ["<Tab>"] = cmp.mapping(function(fallback)
                        if cmp.visible() then
                            cmp.select_next_item()
                        elseif luasnip.expand_or_jumpable() then
                            luasnip.expand_or_jump()
                        else
                            fallback()
                        end
                    end, { "i", "s" }),
                    ["<S-Tab>"] = cmp.mapping(function(fallback)
                        if cmp.visible() then
                            cmp.select_prev_item()
                        elseif luasnip.jumpable(-1) then
                            luasnip.jump(-1)
                        else
                            fallback()
                        end
                    end, { "i", "s" }),
                }),
                sources = cmp.config.sources({
                    { name = "nvim_lsp" },
                    { name = "luasnip" },
                }, {
                    { name = "buffer" },
                    { name = "path" },
                }),
            })
        end,
    },

    ---------------------------------------------------------------------------
    --- PLUGIN : Comment.nvim
    ---------------------------------------------------------------------------
    {
        "numToStr/Comment.nvim",
        config = function()
            require("Comment").setup()
        end,
    },
}

-------------------------------------------------------------------------------
-------------------------------------------------------------------------------
------------------------------------------------------------- Keybinding Helpers
-------------------------------------------------------------------------------
-------------------------------------------------------------------------------
local keybinding_plugins = {
    ---------------------------------------------------------------------------
    --- PLUGIN : which-key.nvim
    ---------------------------------------------------------------------------
    {
        "folke/which-key.nvim",
        event = "VeryLazy",
        config = function()
            require("which-key").setup()
        end,
    },

    ---------------------------------------------------------------------------
    --- PLUGIN : persistence.nvim
    ---------------------------------------------------------------------------
    {
        "folke/persistence.nvim",
        lazy = false,
        config = function()
            -- Store global CWD before any :tcd is set
            vim.g.global_cwd = vim.fn.getcwd()

            local persistence = require("persistence")
            persistence.setup({
                dir = vim.fn.stdpath("state") .. "/sessions/",
            })

            -- Override the current() function to use global CWD
            local config = require("persistence.config")
            local original_current = persistence.current
            persistence.current = function(opts)
                opts = opts or {}
                local cwd = vim.g.global_cwd or vim.fn.getcwd()
                local name = cwd:gsub("[\\/:]+", "%%")
                if config.options.branch and opts.branch ~= false then
                    local branch = persistence.branch()
                    if branch and branch ~= "main" and branch ~= "master" then
                        name = name .. "%%" .. branch:gsub("[\\/:]+", "%%")
                    end
                end
                return config.options.dir .. name .. ".vim"
            end

            -- Auto-load session if nvim started without arguments
            vim.api.nvim_create_autocmd("VimEnter", {
                group = vim.api.nvim_create_augroup("persistence_autoload", { clear = true }),
                callback = function()
                    if vim.fn.argc() == 0 and not vim.g.started_with_stdin then
                        persistence.load()
                    end
                end,
                nested = true,
            })

            -- Manual keymaps
            vim.keymap.set("n", "<leader>qs", function()
                persistence.save()
                vim.notify("Session saved")
            end, { desc = "Save session" })
            vim.keymap.set("n", "<leader>ql", function()
                persistence.load()
            end, { desc = "Load session" })
            vim.keymap.set("n", "<leader>qL", function()
                persistence.select()
            end, { desc = "Select session" })
            vim.keymap.set("n", "<leader>qd", function()
                persistence.stop()
                vim.notify("Session recording stopped")
            end, { desc = "Stop session recording" })
        end,
    },
}

-------------------------------------------------------------------------------
-------------------------------------------------------------------------------
------------------------------------------------------------ AI CLI Integration
-------------------------------------------------------------------------------
-------------------------------------------------------------------------------
local ai_plugins = {
    ---------------------------------------------------------------------------
    --- PLUGIN : opencode.nvim
    ---------------------------------------------------------------------------
    {
        "NickvanDyke/opencode.nvim",
        dependencies = {
            { "folke/snacks.nvim", opts = { input = {}, picker = {}, terminal = {} } },
        },
        config = function()
            -- Required for auto-reload when opencode edits files
            vim.o.autoread = true

            ---@type opencode.Opts
            vim.g.opencode_opts = {
                provider = {
                    enabled = "tmux",
                    tmux = {
                        options = "-h -l 33% -f",
                    },
                },
            }

            -- Keymaps
            -- Ask opencode with context
            vim.keymap.set({ "n", "x" }, "<leader>oa", function()
                require("opencode").ask("@this: ", { submit = false })
            end, { desc = "Ask opencode" })

            -- Submit immediately with current context
            vim.keymap.set({ "n", "x" }, "<leader>oA", function()
                require("opencode").ask("@this: ", { submit = true })
            end, { desc = "Ask opencode (submit)" })

            -- Select from prompts/commands
            vim.keymap.set({ "n", "x" }, "<leader>os", function()
                require("opencode").select()
            end, { desc = "Opencode select action" })

            -- Toggle opencode panel
            vim.keymap.set({ "n", "t" }, "<leader>oo", function()
                require("opencode").toggle()
            end, { desc = "Toggle opencode" })

            -- Operator for adding ranges
            vim.keymap.set({ "n", "x" }, "go", function()
                return require("opencode").operator("@this ")
            end, { desc = "Add range to opencode", expr = true })

            vim.keymap.set("n", "goo", function()
                return require("opencode").operator("@this ") .. "_"
            end, { desc = "Add line to opencode", expr = true })

            -- Scroll opencode
            vim.keymap.set("n", "<leader>ok", function()
                require("opencode").command("session.half.page.up")
            end, { desc = "Scroll opencode up" })

            vim.keymap.set("n", "<leader>oj", function()
                require("opencode").command("session.half.page.down")
            end, { desc = "Scroll opencode down" })

            -- Code review command
            vim.keymap.set("n", "<leader>or", function()
                require("opencode").ask("/review @this", { submit = true })
            end, { desc = "Review current file" })
        end,
    },

}

-------------------------------------------------------------------------------
-------------------------------------------------------------------------------
-- Setup lazy.nvim with all plugin groups
-------------------------------------------------------------------------------
-------------------------------------------------------------------------------
local all_plugins = {}
for _, group in ipairs({ appearance_plugins, filesystem_plugins, movement_plugins, syntax_plugins, keybinding_plugins, ai_plugins }) do
    for _, plugin in ipairs(group) do
        table.insert(all_plugins, plugin)
    end
end

require("lazy").setup(all_plugins)
