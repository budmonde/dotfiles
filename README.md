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
uv run tests/run-environment.py
```

List the named groups declared in the YAML contract:

```text
uv run tests/run-environment.py --list-checks
```

Run one group, such as the common Git worktree check:

```text
uv run tests/run-environment.py --check common-repository
```

Repeat `--check` to run a small set of groups:

```text
uv run tests/run-environment.py --check git --check github-cli
```

The runner loads `tests/environment.yaml` by default.
It is the readable contract for the common-managed links, files, PATH commands, command outcomes, and repository state.
Pass additional YAML files in order to layer machine-specific metadata or named check groups:

```text
uv run tests/run-environment.py --config tests/environment.yaml --config <local-config.yaml>
```

Use `--live` only when running checks declared as live, read-only integrations.
The test code supplies generic primitives only; add or change an expected tool outcome in `tests/environment.yaml`.
The common configuration names the public install surfaces currently covered by the suite.
Local-only credentials, live authentication, and snapshot publication will be added by the local suite or a later publication phase.

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
