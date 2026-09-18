# Installer lifecycle

Common installers use the [`dotbot-install`](https://github.com/budmonde/dotbot-install) lifecycle protocol.
Dotbot recipes select resources and determine installation order.
The plugin validates and invokes each selected resource script without introducing a second catalog.

## Responsibility split

| Layer | Responsibility |
| --- | --- |
| Recipe config | Select and order links, shell actions, cleanup, and resource installers. |
| `dotbot-install` runner | Consume lifecycle CLI flags and invoke unmodified Dotbot. |
| `dotbot-install` directive | Validate path affinity, select the script host, and enforce the lifecycle protocol. |
| Resource installer | Detect state, converge ordinary intent, and perform explicit upgrades. |
| Backend library | Share package-manager or runtime mechanics without selecting resources. |
| Envtest contract | Verify the resulting environment after installation. |

## Layout

| Path | Use |
| --- | --- |
| `install/shared/` | Python installers that run on Windows and Unix. |
| `install/unix/` | Executable, shebang-based Unix installers. |
| `install/windows/` | PowerShell installers. |
| `install/lib/python/lifecycle.py` | Shared npm-global and npm-project backends. |
| `install/lib/unix/lifecycle.sh` | Unix protocol, GitHub release helpers, and the APT backend. |
| `install/lib/windows/Lifecycle.psm1` | Windows protocol, WinGet, and PowerShell Gallery backends. |
| `orchestrate.py` | Shared recipe selection and fragment assembly with Dotbot and envtest workflow adapters. |
| `recipes/` | Shared-before, platform, shared-after, and envtest recipe fragments. |

Platform affinity is structural.
A Windows recipe may reference `install/windows/` or `install/shared/`.
A Unix recipe may reference `install/unix/` or `install/shared/`.
The plugin rejects a mismatched path before running any installer.

## Dotbot surface

Use a list containing an installer command and description.
A scalar command names an installer with no resource arguments.
A nested list supplies an argument vector without shell parsing:

```yaml
- install:
    - [[install/windows/winget.ps1, BurntSushi.ripgrep.MSVC], Installing ripgrep]
    - [[install/windows/node.ps1, -RequestedVersion, "24.19.0"], Installing Node.js]
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
| `update-available` | Recipe intent is satisfied and a newer candidate was discovered. |
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
| `DOTBOT_INSTALL_ONLINE` | Whether online discovery is permitted. |

## Reusing a backend

Use a generic resource command when an existing backend owns all required behavior.

An APT resource receives its package name from the recipe:

```bash
#!/usr/bin/env bash
set -euo pipefail

source "$DOTBOT_INSTALL_REPO_ROOT/install/lib/unix/lifecycle.sh"

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

Import-Module (Join-Path $env:DOTBOT_INSTALL_REPO_ROOT 'install\lib\windows\Lifecycle.psm1') -Force

Invoke-DotbotInstaller {
    Invoke-WinGetPackage -PackageId $PackageId -Operation $Operation -RequestedVersion $RequestedVersion
}
```

A shared npm-global resource receives its package name from the recipe:

```python
import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(os.environ["DOTBOT_INSTALL_REPO_ROOT"]) / "install/lib/python"))

from lifecycle import main, npm_global


package, operation = sys.argv[1:]
raise SystemExit(main(lambda selected, version: npm_global(package, selected, version), [operation]))
```

A shared `uv` source-backed tool keeps its source policy in the thin resource wrapper:

```python
from lifecycle import main, uv_tool


SOURCE = "git+ssh://git@example.com/team/example.git"


raise SystemExit(
    main(lambda operation, version: uv_tool("example", "example", operation, version, source=SOURCE))
)
```

Source-backed tools reject recipe exact versions because the source reference is their version authority.

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

Every logical recipe has a two-digit order and tag,
such as `20-node`.
Its fragments are assembled in this order:

1. `recipes/20-node.before.conf.yaml`, when present.
2. `recipes/windows/20-node.conf.yaml` or `recipes/unix/20-node.conf.yaml`.
3. `recipes/20-node.after.conf.yaml`, when present.

The shared-before and shared-after phases let common preparation and finalization surround platform-specific work.
Base is the ordinary `00-base` recipe and is never selected implicitly.

With no explicit selection,
the launcher reads the gitignored `.install-recipes` machine plan:

```powershell
.\install.ps1
```

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
They assemble each selected recipe's shared and platform `.test.conf.yaml` files and invoke envtest independently of Dotbot.

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

Pass `--only install --dry-run` for a read-only preflight,
or set `DOTBOT_INSTALL_ONLINE=0` to suppress online discovery during an installer run.
Run focused tests with:

```text
python -m unittest tests.test_install_lifecycle -v
```

After a real install,
run `test.ps1` or `test.sh` to verify the recipes in `.install-recipes`,
or pass an explicit `--recipe` selection to test a subset.
