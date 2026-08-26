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

Test a profile with the same name used by its installer:

```text
./test-profile agentic
```

```powershell
.\test-profile.ps1 agentic
```

Profile commands pass only the selected profile's shared and platform test files to envtest.
The default output shows one color-coded status line for every group, expands failures to the failed primitive names, and ends with a summary.
Pass `--verbose` to add detailed diagnostics, durations, and unexpected tracebacks.
Status labels use terminal colors automatically; set `NO_COLOR` to disable them.

The generic test engine is pinned as the `envtest/` submodule.
The root launchers own platform and profile orchestration and pass the selected YAML files to that engine explicitly.
`test.conf.yaml`, `test.unix.conf.yaml`, and `test.windows.conf.yaml` hold the common and platform contracts.
Profile contracts live next to their corresponding profile configuration as `<profile>.test.conf.yaml`.
`test.conf.yaml` contains the platform-neutral command and configuration checks shared by the supported runtime installers.
Platform and profile contracts contain only assertions whose runtime behavior or setup differs by platform or profile.
Use a shared profile contract when its runtime assertions are identical on every platform; add a platform profile contract only when they differ.
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
