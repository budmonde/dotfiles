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

## Installer Development

Dotbot recipes select and order lifecycle-aware resource installers from `install/`.
See [`install/README.md`](install/README.md) for the protocol, shared backends, version ownership, custom-script requirements, and verification commands.

## Environment Tests

Run the common environment suite from the repository root:

```text
./test.sh
```

List the named groups declared in the YAML contract:

```text
./test.sh --list-checks
```

Run one common group:

```text
./test.sh --check git
```

Repeat `--check` to run a small set of groups:

```text
./test.sh --check git --check github-cli
```

On Windows, use the equivalent PowerShell entry point:

```powershell
.\test.ps1 --check git
```

Test an explicit recipe selection with the same selectors used by installation:

```text
./test.sh --recipe agentic
```

```powershell
.\test.ps1 --recipe agentic
```

Without `--recipe`,
the test launcher reads `.install-recipes` and runs the shared and platform test files for every configured recipe.
IDs,
tags,
canonical names,
and numeric ranges resolve through the same logic as installation.
The default output shows one color-coded status line for every group, expands failures to the failed primitive names, and ends with a summary.
Pass `--verbose` to add detailed diagnostics, durations, and unexpected tracebacks.
Status labels use terminal colors automatically; set `NO_COLOR` to disable them.

The generic test engine is pinned as the `envtest/` submodule.
The root `orchestrate.py` control plane owns recipe selection for both installation and testing.
Its test adapter passes the selected YAML files to envtest explicitly.
Base contracts live at `recipes/00-base.test.conf.yaml` and the corresponding platform path.
Other contracts live beside their recipe fragments as `<canonical-recipe>.test.conf.yaml`.
Shared contracts contain platform-neutral checks.
Platform recipe contracts contain only assertions whose runtime behavior or setup differs by platform.
Pass `--config <path>` after the standard layers to add a machine-specific overlay.
Run `./test.sh --check ssh` to verify GitHub SSH authentication.
The SSH command is non-interactive and never accepts or writes host keys.
Other local-only credentials and snapshot publication will be added by the local suite or a later publication phase.

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
