import os
import shutil
import subprocess
import sys
import webbrowser
from pathlib import Path


repo_root = Path(
    os.environ.get("DOTBOT_INSTALL_REPO_ROOT", Path(__file__).resolve().parents[2])
)
sys.path.insert(0, str(repo_root / "install/lib/python"))

from lifecycle import InstallerError, capture, diagnostic, main


HOSTNAME = "github.com"
KEY_ADMIN_SCOPE = "admin:public_key"
DEVICE_URL = "https://github.com/login/device"


def _authentication_state():
    if shutil.which("gh") is None:
        diagnostic("GitHub CLI is required; install the base recipe first.")
        return "blocked", False

    authenticated = capture(
        ["gh", "auth", "status", "--active", "--hostname", HOSTNAME]
    )
    if authenticated.returncode != 0:
        return "absent", False

    key_access = capture(["gh", "api", "/user/keys?per_page=1"])
    return ("current", True) if key_access.returncode == 0 else ("drifted", True)


def _run_authorization(arguments):
    process = subprocess.Popen(
        arguments,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        encoding="utf-8",
        errors="replace",
    )

    browser_opened = False
    for line in process.stdout:
        diagnostic(line.rstrip())
        if "failed to copy one-time code to clipboard" in line.lower():
            diagnostic("GitHub authorization requires a working clipboard.")
            process.terminate()
            process.wait()
            return False
        if DEVICE_URL in line and not browser_opened:
            try:
                browser_opened = webbrowser.open(DEVICE_URL, new=2)
            except (OSError, webbrowser.Error):
                browser_opened = False
            if not browser_opened:
                diagnostic("Unable to open the GitHub authorization page.")
                process.terminate()
                process.wait()
                return False

    return process.wait() == 0 and browser_opened


def github_auth(operation, requested_version):
    if requested_version:
        raise InstallerError("GitHub authentication does not accept a requested version.")

    state, authenticated = _authentication_state()
    if operation == "status" or state in {"current", "blocked"}:
        return state

    if authenticated:
        arguments = [
            "gh",
            "auth",
            "refresh",
            "--hostname",
            HOSTNAME,
            "--clipboard",
            "--scopes",
            KEY_ADMIN_SCOPE,
        ]
    else:
        arguments = [
            "gh",
            "auth",
            "login",
            "--hostname",
            HOSTNAME,
            "--git-protocol",
            "ssh",
            "--web",
            "--clipboard",
            "--skip-ssh-key",
            "--scopes",
            KEY_ADMIN_SCOPE,
        ]

    if not _run_authorization(arguments):
        diagnostic("GitHub authorization did not complete.")
        return "blocked"

    final_state, _ = _authentication_state()
    return final_state


if __name__ == "__main__":
    raise SystemExit(main(github_auth))
