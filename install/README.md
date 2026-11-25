# Installer lifecycle

Common installers use the [`dotbot-install`](https://github.com/budmonde/dotbot-install) lifecycle protocol.
Dotbot recipes select resources and determine installation order.
The plugin validates and invokes each selected resource script without introducing a second catalog.

## Responsibility split

| Layer | Responsibility |
| --- | --- |
| Recipe config | Select and order links, shell actions, cleanup, and resource installers. |
| `dotbot-install` runner | Consume lifecycle CLI flags and invoke unmodified Dotbot. |
| `dotbot-install` directive | Resolve installer paths, launch scripts, and enforce the lifecycle protocol. |
| Resource installer | Detect state, converge ordinary intent, and perform explicit upgrades. |
| Backend library | Share package-manager or runtime mechanics without selecting resources. |
| Envtest contract | Verify the resulting environment after installation. |

## Layout

| Path | Use |
| --- | --- |
| `recipes/<number>-<name>/` | Shared phases, platform fragments, selectors, and Envtest checks for one recipe. |
| `install/resources/` | Dotbot installers, with a subdirectory for each tool that has multiple implementations. |
| `install/select/` | Read-only probes invoked by recipe selectors. |
| `install/keyring-session.py` | Opens an unlocked keyring session on headless Linux. |
| `install/lib/recipe_resolver.py` | Recipe fragment selection and assembly. |
| `install/lib/lifecycle/python/` | Python protocol adapter and npm, uv, keyring, and SSH helpers. |
| `install/lib/lifecycle/bash.sh` | Bash protocol adapter, GitHub release helpers, and the APT backend. |
| `install/lib/lifecycle/PowerShell.psm1` | PowerShell protocol adapter with implementations in `powershell/`. |
| `orchestrate.py` | CLI selection, machine plans, and execution through Dotbot or Envtest. |

Put single-file installers directly in `install/resources/`.
When a tool has separate implementations, keep them together, as in `node/unix.sh` and `node/windows.ps1`.
Each platform recipe names the applicable file, and each installer checks its own platform-specific requirements.
Resolve resource and link paths relative to the consuming checkout root.

## Dotbot surface

Use a list containing an installer command and description.
A scalar command names an installer with no resource arguments.
A nested list supplies an argument vector without shell parsing:

```yaml
- install:
    - [[install/resources/winget.ps1, BurntSushi.ripgrep.MSVC], Installing ripgrep]
    - [[install/resources/node/windows.ps1, -RequestedVersion, "24.19.0"], Installing Node.js]
```

The plugin preflights every entry before execution,
preserves declaration order,
and stops at the first failed installer.
It accepts these forms:

```text
[installer-path, description]
[[installer-path, argument, ...], description]
```

The plugin treats resource arguments as opaque values and appends the selected lifecycle operation.

## Protocol

The plugin invokes one of these forms after any declared resource arguments:

```text
<installer> [arguments...] status
<installer> [arguments...] apply
<installer> [arguments...] upgrade
```

`status` is read-only.
`apply` installs an absent unpinned resource or converges an exact recipe pin,
but it does not advance an existing unpinned resource.
`upgrade` explicitly asks an unpinned manager for its newest candidate.
An exact recipe pin always remains the upper authority,
so upgrade may converge to it but never advance beyond it.

The installer prints exactly one state to standard output and sends diagnostics to standard error.

| State | Meaning |
| --- | --- |
| `absent` | No acceptable installation exists. |
| `current` | The installed resource satisfies recipe intent. |
| `drifted` | Installer-owned state differs from an exact or otherwise declared target. |
| `update-available` | Recipe intent is satisfied and a newer candidate is visible in locally available metadata. |
| `blocked` | The supported resource cannot be inspected or converged safely. |
| `unsupported` | This host or installation variant is intentionally unmanaged. |

A nonzero exit status represents an unexpected installer failure.
After mutation,
`absent`,
`drifted`,
and `blocked` cause the Dotbot action to fail.

The child process receives:

| Variable | Meaning |
| --- | --- |
| `DOTBOT_INSTALL_REPO_ROOT` | Canonical path to the owning repository. |

## Reusing a backend

Use a generic resource command when an existing backend owns all required behavior.

An APT resource receives its package name from the recipe:

```bash
#!/usr/bin/env bash
set -euo pipefail

source "$DOTBOT_INSTALL_REPO_ROOT/install/lib/lifecycle/bash.sh"

package="${1:?APT package name is required}"
shift
installer_apt_package "$package" "$@"
```

A WinGet resource receives its package ID from the recipe:

```powershell
param(
    [Parameter(Mandatory, Position = 0)][string]$PackageId,
    [Parameter(Position = 1)][ValidateSet('status', 'apply', 'upgrade')][string]$Operation = 'apply',
    [string]$RequestedVersion
)

Import-Module (Join-Path $env:DOTBOT_INSTALL_REPO_ROOT 'install\lib\lifecycle\PowerShell.psm1') -Force

Invoke-DotbotInstaller {
    Invoke-WinGetPackage -PackageId $PackageId -Operation $Operation -RequestedVersion $RequestedVersion
}
```

A Python resource adds `install/lib/` to its import path.
The npm resource receives the package name from its recipe:

```python
from lifecycle.python import core, npm


def install(operation, requested_version):
    return npm.global_package(package, operation=operation, requested_version=requested_version)
```

Pass the handler to `core.main()` with the lifecycle arguments.
A uv resource uses the same controls and can supply a source:

```python
from lifecycle.python import uv


def install(operation, requested_version):
    return uv.tool(
        "example",
        "example",
        operation=operation,
        requested_version=requested_version,
        source="git+ssh://git@example.com/team/example.git",
    )
```

An exact recipe version can accompany a Git source requirement.
The installer verifies both the selected source and the package version reported by that source.

## Writing a custom installer

Use a custom resource script for release-asset selection,
transactional replacement,
local state convergence,
variant preservation,
or another resource-specific policy.
Move mechanics into a backend library only after at least two installers share the same semantics.

A custom installer must:

- derive repository paths from `DOTBOT_INSTALL_REPO_ROOT`;
- keep `status` free of mutations;
- make `apply` idempotent and version-preserving;
- honor or reject any resource arguments explicitly;
- verify the installed result before returning success;
- treat an unowned installation as `unsupported` or `blocked` rather than overwriting it;
- use standard error for progress and diagnostics;
- clean staging artifacts and preserve the prior owned installation on failure.

Simple repository commands remain Dotbot `shell` entries.

## Recipe selection

Every recipe has a directory named by its two-digit order and tag, such as `recipes/20-node/`.
The shell and PowerShell launchers select the Unix and Windows families respectively.
Within that directory, installation assembles `before.conf.yaml`, the chosen platform fragment, and `after.conf.yaml` in that order, omitting absent files.
Envtest uses `test.conf.yaml` followed by the selected platform's test fragment.
A recipe can provide only shared install fragments.

Use `unix.conf.yaml` or `windows.conf.yaml` for a platform with one implementation.
Its optional Envtest fragment has the same stem and ends in `.test.conf.yaml`.
When the implementation branches, use a directory of the same stem containing `select.yaml`.
See [keyring's Unix selector](../recipes/04-keyring/unix/select.yaml) for the format.
Use a selector directory's `before.conf.yaml`, `after.conf.yaml`, and `test.conf.yaml` for steps shared by its leaves.
They wrap the selected install fragment and precede the selected Envtest fragment, just as they do at the recipe root.

Each selector declares a `probe` mapping from fact names to command vectors and a `select` list of routes.
Probes name Python scripts under `install/select/` relative to the checkout root and pass literal arguments.
A probe reports one value on stdout, with diagnostics on stderr.
Each route requires an exact match for all facts in `when`.
Declare the cheapest discriminating fact first so a route can stop before running additional probes.

The resolver requires one matching route.
Its `target` names a sibling leaf or another selector directory.
A `null` target explicitly uses the shared fragments.
Branch names have meaning through the selector that points to them.
Planning fails when a probe fails, a selected target is missing, or the routes yield zero or multiple matches.
Each selected recipe resolves its install and test fragments together.
The resolver loads Dotbot's vendored PyYAML on demand when it first encounters a selector.

Base is the ordinary `00-base` recipe and is never selected implicitly.
With no explicit selection,
the launcher reads the gitignored `.install-recipes` machine plan:

```powershell
.\install.ps1
```

Use one canonical recipe name per line.
Blank lines and lines beginning with `#` are ignored.

`--recipe` replaces the machine plan.
Selectors may be canonical names,
numeric IDs,
tags,
or inclusive numeric ranges:

```powershell
.\install.ps1 --recipe base
.\install.ps1 --recipe dev node agentic
.\install.ps1 --recipe 10 20 30
.\install.ps1 --recipe 10...30
```

Selections must be unique and strictly increasing.
The launcher rejects invalid order rather than sorting it.
`--upgrade` and ordinary Dotbot arguments may appear without a `--` bridge:

```powershell
.\install.ps1 --recipe dev node --only install --dry-run
.\install.ps1 --only install --dry-run --upgrade
```

`test.ps1` and `test.sh` resolve the same default machine plan and `--recipe` selectors.
They pass the shared and selected test fragments to Envtest.

The orchestrator defaults to the checkout that contains it.
Launchers can pass `--repo-root PATH` to select another checkout's machine plan and recipes while reusing the Dotbot and Envtest pins beside the orchestrator.

## Verification

Validate the selected recipes without running installers:

```powershell
.\install.ps1 --only install --dry-run
.\install.ps1 --recipe node --only install --dry-run
```

```bash
./install.sh --only install --dry-run
./install.sh --recipe node --only install --dry-run
```

Pass `--only install --dry-run` for a read-only preflight.
Installer `status` uses installed state and locally available package metadata without discovering upstream releases.
Run focused tests with:

```text
python -m unittest tests.test_install_lifecycle -v
```

After a real install,
run `test.ps1` or `test.sh` to verify the recipes in `.install-recipes`,
or pass an explicit `--recipe` selection to test a subset.
