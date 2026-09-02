import re
import shutil
from typing import Optional

from .core import InstallerError, capture, online_allowed, report


def uv_tool(
    package: str,
    executable: str,
    operation: str,
    requested_version: str = "",
) -> str:
    uv = shutil.which("uv")
    if uv is None:
        return "blocked"

    state = _uv_tool_state(uv, package, executable, requested_version)
    if operation == "status" or state == "unsupported":
        return state
    if state == "current" and (operation == "apply" or requested_version):
        return state
    if not online_allowed():
        return "blocked"

    installed_version = _uv_tool_installed_version(uv, package)
    if operation == "upgrade" and state == "current":
        arguments = [uv, "tool", "upgrade", package]
    else:
        target = (
            "{}=={}".format(package, requested_version)
            if requested_version
            else package
        )
        arguments = [uv, "tool", "install"]
        if installed_version is not None:
            arguments.append("--force")
        arguments.append(target)

    result = capture(arguments)
    report(result)
    if result.returncode != 0:
        raise InstallerError("uv failed to install {}".format(package))

    final_state = _uv_tool_state(uv, package, executable, requested_version)
    if final_state != "current":
        raise InstallerError("{} remains {} after installation".format(package, final_state))
    return final_state


def _uv_tool_installed_version(uv: str, package: str) -> Optional[str]:
    result = capture([uv, "tool", "list"])
    if result.returncode != 0:
        report(result)
        raise InstallerError("uv could not list managed tools")
    match = re.search(
        r"(?m)^{} v([^\s]+)".format(re.escape(package)), result.stdout
    )
    return match.group(1) if match else None


def _uv_tool_state(
    uv: str,
    package: str,
    executable: str,
    requested_version: str = "",
) -> str:
    installed_version = _uv_tool_installed_version(uv, package)
    executable_path = shutil.which(executable)
    if installed_version is None:
        return "unsupported" if executable_path else "absent"
    if executable_path is None or capture([executable_path, "--help"]).returncode != 0:
        return "drifted"
    if requested_version and installed_version != requested_version:
        return "drifted"
    return "current"
