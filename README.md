# dotfiles

## Windows Bootstrap

On a fresh Windows machine:

1. Set up a local account: upon initial boot, open command prompt (`Shift + F10`) and run `OOBE\BYPASSNRO`.
2. Run in PowerShell (as admin):

```powershell
irm https://raw.githubusercontent.com/budmonde/dotfiles/main/bootstrap.ps1 | iex
```

This ensures winget is on PATH, installs git and python via winget, configures git to use Windows OpenSSH, and enables the ssh-agent service.
Then follow the printed next steps to add SSH keys, clone, and run `install.ps1`.

## Neovim Plugins to Consider

Quality of life plugins that may be worth adding:

| Plugin | Purpose |
|--------|---------|
| [nvim-autopairs](https://github.com/windwp/nvim-autopairs) | Auto-close brackets, quotes |
| [indent-blankline.nvim](https://github.com/lukas-reineke/indent-blankline.nvim) | Visual indent guides |
| [todo-comments.nvim](https://github.com/folke/todo-comments.nvim) | Highlight TODO/FIXME/NOTE comments |
| [trouble.nvim](https://github.com/folke/trouble.nvim) | Better diagnostics list |
| [harpoon](https://github.com/ThePrimeagen/harpoon) | Quick file marks/navigation |
| [undotree](https://github.com/mbbill/undotree) | Visual undo history |
| [noice.nvim](https://github.com/folke/noice.nvim) | Fancy cmdline/messages UI |
| [oil.nvim](https://github.com/stevearc/oil.nvim) | Edit filesystem like a buffer |
