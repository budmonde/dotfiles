# Installer lifecycle

Common installers use the [`dotbot-install`](https://github.com/budmonde/dotbot-install) lifecycle protocol.
Dotbot profiles still select resources and determine installation order.
Each entry in an `install` directive pairs a resource script with the description Dotbot prints while invoking it.

There is no second recipe catalog under `install/`.

## Responsibility split

| Layer | Responsibility |
| --- | --- |
| Dotbot config | Select and order resource installers. |
| `dotbot-install` plugin | Validate path affinity, invoke the correct script host, and enforce the protocol. |
| Resource installer | Detect state, apply an idempotent install, and perform explicit upgrades. |
| Backend library | Share package-manager or runtime mechanics without selecting resources. |
| Envtest contract | Verify the resulting user environment after installation. |

## Layout

| Path | Use |
| --- | --- |
| `install/shared/` | Python installers that run on Windows and Unix. |
| `install/unix/` | Executable, shebang-based Unix installers. |
| `install/windows/` | PowerShell installers. |
| `install/lib/python/lifecycle.py` | Shared npm-global and npm-project backends. |
| `install/lib/unix/lifecycle.sh` | Unix protocol, GitHub release helpers, and the APT backend. |
| `install/lib/windows/Lifecycle.psm1` | Windows protocol, WinGet, and PowerShell Gallery backends. |

Platform affinity is structural.
A Windows profile may reference `install/windows/` or `install/shared/`, while a Unix profile may reference `install/unix/` or `install/shared/`.
The plugin rejects a mismatched path before it runs the script.

## Dotbot surface

Use the same path-description pair shape as Dotbot's `shell` directive.
Even a single resource remains a list containing one pair:

```yaml
- install:
    - [install/windows/winget/ripgrep.ps1, Installing ripgrep]
```

Group contiguous resources into an ordered list:

```yaml
- install:
    - [install/windows/winget/ripgrep.ps1, Installing ripgrep]
    - [install/windows/winget/rclone.ps1, Installing rclone]
    - [install/windows/winget/neovim.ps1, Installing Neovim]
```

The plugin preflights every list entry before executing any of them, preserves declaration order, and stops at the first execution failure.
Each entry contains exactly a path and a non-empty description rather than a per-installer configuration mapping.
Keep dependent configuration actions around install blocks in Dotbot.
For example, the desktop profile installs AutoHotkey, restarts its linked startup script, installs PowerToys, and then applies PowerToys settings in that order.

## Protocol

The plugin invokes one of these forms:

```text
<installer> status
<installer> apply
<installer> upgrade [requested-version]
```

`status` is read-only.
`apply` installs an absent resource or repairs drift, but it must not advance a version.
`upgrade` is the only operation that may select a newer version or update repository lock data.

The installer prints exactly one state to standard output and sends all diagnostics to standard error.

| State | Meaning |
| --- | --- |
| `absent` | The resource is not installed. |
| `current` | The installed resource matches its owned target. |
| `drifted` | The resource exists but does not match its owned target. |
| `update-available` | The owned target is installed and a newer version is discoverable. |
| `blocked` | A required dependency or safe convergence path is unavailable. |
| `unsupported` | This host or preserved installation variant is intentionally unmanaged. |

A nonzero exit status indicates an installer failure rather than a lifecycle state.
After mutation, `absent`, `drifted`, and `blocked` cause the Dotbot action to fail because convergence was not achieved.

## Reusing a backend

Use a thin wrapper when an existing backend owns all required behavior.

An APT resource needs only its package name:

```bash
#!/usr/bin/env bash
set -euo pipefail

source "$DOTBOT_INSTALL_REPO_ROOT/install/lib/unix/lifecycle.sh"

installer_apt_package cmake "$@"
```

A WinGet resource needs only its package ID:

```powershell
param(
    [ValidateSet('status', 'apply', 'upgrade')][string]$Operation = 'apply',
    [string]$RequestedVersion
)

Import-Module (Join-Path $env:DOTBOT_INSTALL_REPO_ROOT 'install\lib\windows\Lifecycle.psm1') -Force

Invoke-DotbotInstaller {
    Invoke-WinGetPackage -PackageId 'Kitware.CMake' -Operation $Operation -RequestedVersion $RequestedVersion
}
```

A shared npm-global resource delegates through the Python backend:

```python
import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(os.environ["DOTBOT_INSTALL_REPO_ROOT"]) / "install/lib/python"))

from lifecycle import main, npm_global


raise SystemExit(main(lambda operation, version: npm_global("example-package", operation, version)))
```

## Writing a custom installer

Use a custom resource script when the target needs release-asset selection, transactional replacement, local configuration convergence, variant preservation, or another resource-specific policy.
Keep generic mechanics in the appropriate backend library only after at least two resource installers share the same semantics.

A custom installer must:

- derive repository paths from `DOTBOT_INSTALL_REPO_ROOT`;
- keep `status` free of mutations;
- make `apply` idempotent and version-preserving;
- verify the installed result before returning a successful state;
- update version locks only after successful verification;
- treat an installation it does not own as `unsupported` or `blocked` instead of overwriting it;
- use standard error for progress and diagnostics;
- clean up staging artifacts and preserve the prior installation on failure.

The plugin also provides `DOTBOT_INSTALL_ID`, `DOTBOT_INSTALL_STATE_DIR`, `DOTBOT_INSTALL_LOCK_FILE`, `DOTBOT_INSTALL_ONLINE`, and the selected operation and version as environment variables.
See the plugin README for the complete execution contract.

## Version ownership

Do not introduce a universal lock entry when another source already owns the version.
Package-manager resources use the package manager's installed and candidate versions.
The Node.js installers use `profiles/node-version` as an exact cross-platform lock and update it only after an upgraded runtime verifies successfully.
The git-auditor npm project follows its checked-in `package-lock.json` and records the applied manifest digest below `node_modules`.

When a resource needs a repository-owned version and has no existing authority, use the conventional `install/installer.lock.yaml` path exposed by `DOTBOT_INSTALL_LOCK_FILE`.
Add a lock schema only with the first real consumer rather than speculative entries for package-manager resources.

## Verification

Validate config loading and path affinity without running installers:

```powershell
.\install.ps1 --only install --dry-run
.\install-profile.ps1 node -- --only install --dry-run
```

```bash
./install.sh --only install --dry-run
./install-profile node -- --only install --dry-run
```

Run a read-only, offline-aware state pass by setting `DOTBOT_INSTALL_OPERATION=status` and `DOTBOT_INSTALL_ONLINE=0` before the same command.
Run the backend and manifest tests with `python -m unittest tests.test_install_lifecycle -v`.
After a real install, use the corresponding root or profile test launcher to verify the environment contract.
