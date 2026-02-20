# AGENTS.md - Dotfiles Repository

This is a personal dotfiles repository for managing shell, editor, and development tool
configurations. It uses **dotbot** for symlink management and git submodules for plugins.

## Repository Structure

```
dotfiles/
├── install              # Main installation script (runs dotbot)
├── install.conf.yaml    # Dotbot configuration - defines symlinks
├── dotbot/              # Dotbot submodule
├── bash/                # Bash-specific configs
├── zsh/                 # Zsh-specific configs (plugins as submodules)
├── shell/               # Shared shell configs (aliases, functions)
├── vim/                 # Vim configuration (vimrc, plugins as submodules)
├── nvim/                # Neovim configuration (Lua, lazy.nvim)
├── bin/                 # Custom scripts
├── tmux.conf            # Tmux configuration
├── gitconfig            # Git configuration
└── ssh/                 # SSH configuration
```

## Build/Install Commands

| Command | Description |
|---------|-------------|
| `./install` | Main installation - creates symlinks and initializes submodules |
| `git submodule update --init --recursive` | Initialize/update all plugin submodules |

This is a configuration repository - there are no build, lint, or test commands.

## Adding New Plugins

### Vim Plugins (git submodules)
```bash
cd ~/.dotfiles
git submodule add <repo-url> vim/pack/vendor/start/<plugin-name>
git submodule update --init --recursive
```

### Zsh Plugins (git submodules)
```bash
git submodule add <repo-url> zsh/plugins/<plugin-name>
# Then source in zsh/plugins.zsh
```

### Neovim Plugins (lazy.nvim)
Add plugin specs to `nvim/lua/config/lazy.lua` in the appropriate plugin group:
- `appearance_plugins` - UI/theme/statusline
- `filesystem_plugins` - File navigation, git integration
- `movement_plugins` - Navigation and text manipulation
- `syntax_plugins` - LSP, treesitter, completion
- `keybinding_plugins` - Keybinding helpers
- `ai_plugins` - AI/LLM integration

## Code Style Guidelines

### Shell Scripts (bash/zsh)

**File Organization:**
- Shared code goes in `shell/` (sourced by both bash and zsh)
- Shell-specific code goes in `bash/` or `zsh/` directories
- Use `.sh` extension for shared scripts, `.bash`/`.zsh` for shell-specific

**Functions:**
```bash
# Use local variables in functions
function_name() {
    local var="value"
    # ...
}
```

**Path Manipulation:**
- Use the `path_prepend`, `path_append`, `path_remove` functions from `shell/functions.sh`
- Never modify PATH directly without removing duplicates

**Local Overrides:**
- Machine-specific config: `~/.shellrc_local`, `~/.bashrc_local`, `~/.zshrc_local`
- Never commit machine-specific settings to the repo

### Vim Configuration (vimrc)

**Section Organization:** Use comment banners for major sections:
```vim
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
""" PLUGIN : plugin-name
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
```

**Plugin Configuration:**
- Plugin settings immediately follow the section banner
- Keep related keymaps with their plugin configuration

**Keybindings:**
- Leader key: `,` (comma)
- Local leader: `\` (backslash)
- Alt+key for navigation (h/j/k/l for pane/split movement)
- Ctrl+key for common operations

**Indentation:**
- 4 spaces (expandtab)
- Consistent with tabstop=4, shiftwidth=4, softtabstop=4

### Neovim Lua Configuration

**File Location:** All Neovim-specific Lua in `nvim/lua/config/`

**Plugin Specification Format:**
```lua
{
    "author/plugin-name",
    dependencies = { "dep1", "dep2" },
    config = function()
        require("plugin").setup({
            -- options
        })
        -- keymaps related to this plugin
        vim.keymap.set("n", "<key>", function_or_command, { desc = "Description" })
    end,
}
```

**Section Banners:** Use Lua comment style matching vimrc:
```lua
-------------------------------------------------------------------------------
--- PLUGIN : plugin-name
-------------------------------------------------------------------------------
```

**Settings that should match vimrc:**
- Neovim sources `vim/vimrc` via `nvim/init.vim`
- Set `vim.g.skip_colorscheme = 1` before loading vimrc (lazy.nvim handles colorscheme)
- Keybindings should mirror Vim equivalents where possible

### Git Configuration

**Aliases:** Keep aliases short and mnemonic:
- Two-letter for common operations: `st`, `co`, `ci`, `ff`
- Three-letter for variants: `ssl` (short smartlog)

**Include Local Config:**
```gitconfig
[includeIf "hasconfig:~/.gitconfig_local"]
    path = ~/.gitconfig_local
```

### Tmux Configuration

**Prefix:** `C-a` (Ctrl+a), not default `C-b`

**Keybindings:**
- Alt+h/j/k/l: Navigate between panes (integrates with vim-tmux-navigator)
- Alt+H/L: Navigate between windows
- `v`: Vertical split, `h`: Horizontal split (mnemonic for resulting layout)

## Key Configuration Patterns

### Local Override Pattern
All configs support machine-specific overrides via `*_local` files:
- `~/.shellrc_local` - Shared shell local config
- `~/.bashrc_local` - Bash-specific local config
- `~/.zshrc_local` - Zsh-specific local config
- `~/.gitconfig_local` - Git local config
- `g:use_nerd_fonts` in vimrc - Set to 0 for machines without Nerd Fonts

### Vim-Tmux Integration
Navigation between vim splits and tmux panes uses Alt+h/j/k/l:
- `vim-tmux-navigator` plugin in Vim/Neovim
- Corresponding tmux bindings in `tmux.conf`

### WSL Support
WSL-specific features are conditionally enabled:
- Clipboard sync in vimrc (`<Leader>x` toggle)
- tmux clipboard integration via `clip.exe`

## Common Editing Tasks

### Adding a New Alias
Edit `shell/aliases.sh` - available in both bash and zsh.

### Adding a New Vim Plugin (submodule)
```bash
git submodule add https://github.com/author/plugin vim/pack/vendor/start/plugin
```
Then configure in `vim/vimrc` under a PLUGIN section.

### Adding a New Neovim Plugin (lazy.nvim)
Add to appropriate plugin group in `nvim/lua/config/lazy.lua`.

### Updating All Submodules
```bash
git submodule update --init --recursive
```

### Creating a New Symlink
Add entry to `install.conf.yaml` under the `link` section:
```yaml
- link:
    ~/.target: source/path  # Explicit source
    ~/.target:              # Implicit: uses filename without dot
```

## Files to Never Commit

- `REFACTOR.md` - Local tracking file for refactoring tasks; not part of the repo
