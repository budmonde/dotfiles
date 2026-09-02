import hashlib
import json
import shutil
from pathlib import Path
from typing import Optional

from .core import InstallerError, capture, diagnostic, online_allowed, report


def npm_global(package: str, operation: str, requested_version: str = "") -> str:
    npm = shutil.which("npm")
    if npm is None:
        return "blocked"

    installed_version = _npm_installed_version(npm, package)
    state = _npm_state(npm, package, installed_version, requested_version)
    if operation == "status":
        return state
    if state in {"current", "update-available"} and (
        operation == "apply" or requested_version
    ):
        return state

    target = package
    if requested_version:
        target = "{}@{}".format(package, requested_version)
    result = capture([npm, "install", "--global", target, "--no-audit", "--no-fund"])
    report(result)
    if result.returncode != 0:
        raise InstallerError("npm failed to install {}".format(target))

    installed_version = _npm_installed_version(npm, package)
    if installed_version is None:
        raise InstallerError("npm did not report {} after installation".format(package))
    if requested_version and installed_version != requested_version:
        raise InstallerError(
            "npm installed {} {}, expected {}".format(
                package, installed_version, requested_version
            )
        )
    return _npm_state(npm, package, installed_version, requested_version)


def npm_project(project: Path, operation: str, requested_version: str = "") -> str:
    if requested_version:
        raise InstallerError("npm project installers do not accept a requested version")
    npm = shutil.which("npm")
    if npm is None:
        return "blocked"
    if not (project / "package.json").is_file():
        raise InstallerError("Missing package.json in {}".format(project))

    state = _npm_project_state(npm, project)
    if operation == "status" or state == "current":
        return state

    result = capture(
        [npm, "install", "--silent", "--no-audit", "--no-fund"], cwd=project
    )
    report(result)
    if result.returncode != 0:
        raise InstallerError("npm install failed in {}".format(project))
    _write_npm_project_stamp(project)
    if _npm_project_state(npm, project) != "current":
        raise InstallerError("npm dependencies remain inconsistent in {}".format(project))
    return "current"


def _npm_installed_version(npm: str, package: str) -> Optional[str]:
    result = capture([npm, "list", "--global", package, "--depth=0", "--json"])
    try:
        payload = json.loads(result.stdout or "{}")
    except json.JSONDecodeError as error:
        raise InstallerError("npm returned invalid package metadata: {}".format(error))
    dependency = payload.get("dependencies", {}).get(package)
    if not isinstance(dependency, dict):
        return None
    version = dependency.get("version")
    return version if isinstance(version, str) and version else None


def _npm_latest_version(npm: str, package: str) -> Optional[str]:
    if not online_allowed():
        return None
    result = capture([npm, "view", package, "version", "--json"])
    if result.returncode != 0:
        diagnostic("Could not query the latest npm version for {}".format(package))
        return None
    try:
        value = json.loads(result.stdout)
    except json.JSONDecodeError:
        diagnostic("npm returned invalid latest-version metadata for {}".format(package))
        return None
    return value if isinstance(value, str) and value else None


def _npm_state(
    npm: str,
    package: str,
    installed_version: Optional[str],
    requested_version: str = "",
) -> str:
    if installed_version is None:
        return "absent"
    if requested_version and installed_version != requested_version:
        return "drifted"
    latest = _npm_latest_version(npm, package)
    if latest and latest != installed_version:
        return "update-available"
    return "current"


def _npm_project_state(npm: str, project: Path) -> str:
    result = capture([npm, "list", "--depth=0", "--json"], cwd=project)
    if result.returncode == 0 and _npm_project_stamp_matches(project):
        return "current"
    return "drifted" if (project / "node_modules").exists() else "absent"


def _npm_project_manifest(project: Path) -> Path:
    lockfile = project / "package-lock.json"
    return lockfile if lockfile.is_file() else project / "package.json"


def _npm_project_stamp(project: Path) -> Path:
    return project / "node_modules" / ".dotbot-install-manifest.sha256"


def _npm_project_manifest_digest(project: Path) -> str:
    return hashlib.sha256(_npm_project_manifest(project).read_bytes()).hexdigest()


def _npm_project_stamp_matches(project: Path) -> bool:
    stamp = _npm_project_stamp(project)
    if not stamp.is_file():
        return False
    return stamp.read_text(encoding="utf-8").strip() == _npm_project_manifest_digest(
        project
    )


def _write_npm_project_stamp(project: Path) -> None:
    stamp = _npm_project_stamp(project)
    stamp.parent.mkdir(parents=True, exist_ok=True)
    stamp.write_text(_npm_project_manifest_digest(project) + "\n", encoding="utf-8")
