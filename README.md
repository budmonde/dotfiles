# TODO

- Remove .spl file from vim spelling dir

## Installing Neovim on Remote Servers

On servers without root access or where package managers have outdated versions, use the AppImage:

```bash
mkdir -p ~/.local/bin
curl -L -o ~/.local/bin/nvim.appimage https://github.com/neovim/neovim/releases/latest/download/nvim-linux-x86_64.appimage
chmod +x ~/.local/bin/nvim.appimage
ln -s nvim.appimage ~/.local/bin/nvim
```

Ensure `~/.local/bin` is in your PATH (already configured in `shell/bootstrap.sh`).

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
