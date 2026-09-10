import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import webbrowser
from pathlib import Path


repo_root = Path(
    os.environ.get("DOTBOT_INSTALL_REPO_ROOT", Path(__file__).resolve().parents[2])
)
sys.path.insert(0, str(repo_root / "install/lib/python"))

from lifecycle import InstallerError, diagnostic, main


HOSTNAME = "github.com"
KEY_ADMIN_SCOPE = "admin:public_key"
DEVICE_URL = "https://github.com/login/device"
TOKEN_FIELD = re.compile(r"(?m)^\s*oauth_token\s*:")
TOKEN_ENVIRONMENT_VARIABLES = (
    "GH_ENTERPRISE_TOKEN",
    "GH_TOKEN",
    "GITHUB_ENTERPRISE_TOKEN",
    "GITHUB_TOKEN",
)
KEYRING_BOOTSTRAP_ATTRIBUTES = (
    "application",
    "dotfiles",
    "resource",
    "github-auth-keyring-initialization",
)


def _config_directory():
    override = os.environ.get("GH_CONFIG_DIR")
    if override:
        return Path(override).expanduser()
    config_home = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config"))
    return config_home / "gh"


def _plaintext_token_present(directory=None):
    hosts = (directory or _config_directory()) / "hosts.yml"
    if not hosts.is_file():
        return False
    return TOKEN_FIELD.search(hosts.read_text(encoding="utf-8")) is not None


def _active_account(result):
    try:
        accounts = json.loads(result.stdout).get("hosts", {}).get(HOSTNAME, [])
    except (AttributeError, json.JSONDecodeError):
        return None
    return next((account for account in accounts if account.get("active")), None)


def _command_environment(config_directory=None):
    environment = os.environ.copy()
    for name in TOKEN_ENVIRONMENT_VARIABLES:
        environment.pop(name, None)
    if config_directory is not None:
        environment["GH_CONFIG_DIR"] = str(config_directory)
    return environment


def _capture(arguments):
    return subprocess.run(
        arguments,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        encoding="utf-8",
        errors="replace",
        check=False,
        env=_command_environment(),
    )


def _authentication_state():
    if shutil.which("gh") is None:
        diagnostic("GitHub CLI is required; install the base recipe first.")
        return "blocked", False, False

    if _plaintext_token_present():
        diagnostic("GitHub CLI credentials must not be stored in hosts.yml.")
        return "drifted", False, True

    authenticated = _capture(
        [
            "gh",
            "auth",
            "status",
            "--active",
            "--hostname",
            HOSTNAME,
            "--json",
            "hosts",
        ]
    )
    account = _active_account(authenticated)
    if account is None or account.get("state") != "success":
        return "absent", False, False
    if account.get("tokenSource") != "keyring":
        diagnostic("GitHub CLI authentication must use the operating-system keyring.")
        return "drifted", False, False

    key_access = _capture(["gh", "api", "/user/keys?per_page=1"])
    if key_access.returncode == 0:
        return "current", True, False
    return "drifted", True, False


def _prepare_auth_directory(target):
    target.mkdir(mode=0o700, exist_ok=True)
    source = _config_directory()
    for name in ("config.yml", "hosts.yml"):
        source_file = source / name
        if not source_file.is_file():
            continue
        content = source_file.read_text(encoding="utf-8")
        if name == "hosts.yml" and TOKEN_FIELD.search(content):
            diagnostic("Migrate the existing plaintext GitHub credential manually first.")
            return False
        target_file = target / name
        target_file.write_text(content, encoding="utf-8")
        target_file.chmod(0o600)
    return True


def _publish_auth_metadata(source):
    source_hosts = source / "hosts.yml"
    if not source_hosts.is_file():
        diagnostic("GitHub CLI did not write host metadata after authentication.")
        return False
    content = source_hosts.read_text(encoding="utf-8")
    if TOKEN_FIELD.search(content):
        diagnostic("GitHub CLI fell back to plaintext credential storage.")
        return False

    destination_directory = _config_directory()
    destination_directory.mkdir(parents=True, exist_ok=True)
    destination = destination_directory / "hosts.yml"
    descriptor, temporary_name = tempfile.mkstemp(
        prefix=".hosts.yml.", dir=str(destination_directory)
    )
    os.close(descriptor)
    temporary = Path(temporary_name)
    try:
        temporary.write_text(content, encoding="utf-8")
        temporary.replace(destination)
    finally:
        if temporary.exists():
            temporary.unlink()
    return True


def _prepare_linux_keyring():
    if not sys.platform.startswith("linux"):
        return True

    secret_tool = shutil.which("secret-tool")
    if secret_tool is None:
        diagnostic("Secret Service tools are required for secure GitHub authentication.")
        return False

    diagnostic("Unlock or create the Secret Service keyring when prompted.")
    stored = subprocess.run(
        [
            secret_tool,
            "store",
            "--label=Dotfiles keyring initialization",
            *KEYRING_BOOTSTRAP_ATTRIBUTES,
        ],
        input="initialization",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        encoding="utf-8",
        errors="replace",
        check=False,
        env=_command_environment(),
    )
    if stored.returncode != 0:
        diagnostic("Unable to initialize or unlock the Secret Service keyring.")
        return False

    cleared = subprocess.run(
        [secret_tool, "clear", *KEYRING_BOOTSTRAP_ATTRIBUTES],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        encoding="utf-8",
        errors="replace",
        check=False,
        env=_command_environment(),
    )
    if cleared.returncode != 0:
        diagnostic("Unable to remove the temporary keyring initialization item.")
        return False
    return True


def _run_authorization(arguments):
    if not _prepare_linux_keyring():
        return False

    with tempfile.TemporaryDirectory(prefix="github-auth-") as directory:
        config_directory = Path(directory)
        if not _prepare_auth_directory(config_directory):
            return False

        process = subprocess.Popen(
            arguments,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            encoding="utf-8",
            errors="replace",
            env=_command_environment(config_directory),
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

        if process.wait() != 0 or not browser_opened:
            return False
        return _publish_auth_metadata(config_directory)


def github_auth(operation, requested_version):
    if requested_version:
        raise InstallerError("GitHub authentication does not accept a requested version.")

    state, authenticated, plaintext = _authentication_state()
    if operation == "status" or state in {"current", "blocked"}:
        return state
    if plaintext:
        diagnostic("Remove the plaintext GitHub credential before rerunning this recipe.")
        return "blocked"

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

    final_state, _, _ = _authentication_state()
    return final_state


if __name__ == "__main__":
    raise SystemExit(main(github_auth))
