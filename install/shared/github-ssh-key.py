import json
import os
import re
import shutil
import sys
from pathlib import Path


repo_root = Path(
    os.environ.get("DOTBOT_INSTALL_REPO_ROOT", Path(__file__).resolve().parents[2])
)
sys.path.insert(0, str(repo_root / "install/lib/python"))

from lifecycle import InstallerError, capture, diagnostic, main, report


HOSTNAME = "github.com"
MACHINE_ID_PATTERN = re.compile(r"^[a-z0-9][a-z0-9._-]{0,63}$")


def _machine_id():
    value = os.environ.get("ENVTEST_MACHINE_ID", "").strip()
    if not value:
        diagnostic("Set ENVTEST_MACHINE_ID before managing the GitHub SSH key.")
        return None
    if MACHINE_ID_PATTERN.fullmatch(value) is None:
        diagnostic(
            "ENVTEST_MACHINE_ID must be lowercase and contain only letters, digits, dots, underscores, or hyphens."
        )
        return None
    return value


def _key_paths():
    private_key = Path.home() / ".ssh" / "git" / "github_ed25519"
    return private_key, Path(str(private_key) + ".pub")


def _public_identity(value):
    fields = value.strip().split()
    return tuple(fields[:2]) if len(fields) >= 2 else None


def _local_key(private_key, public_key):
    private_exists = private_key.is_file()
    public_exists = public_key.is_file()
    if not private_exists and not public_exists:
        return "absent", None
    if not private_exists or not public_exists:
        diagnostic("The managed GitHub SSH key pair is incomplete.")
        return "drifted", None

    try:
        public_identity = _public_identity(public_key.read_text(encoding="utf-8"))
    except OSError as error:
        diagnostic("Unable to read the managed GitHub public key: {}".format(error))
        return "blocked", None

    if public_identity is None or public_identity[0] != "ssh-ed25519":
        diagnostic("The managed GitHub public key is not a valid Ed25519 key.")
        return "drifted", None

    derived = capture(["ssh-keygen", "-y", "-f", str(private_key)])
    if derived.returncode != 0 or _public_identity(derived.stdout) != public_identity:
        report(derived)
        diagnostic("The managed GitHub private and public keys do not match.")
        return "drifted", None
    return "current", public_identity


def _remote_keys():
    result = capture(["gh", "api", "/user/keys?per_page=100"])
    if result.returncode != 0:
        report(result)
        return None
    try:
        keys = json.loads(result.stdout)
    except json.JSONDecodeError:
        diagnostic("GitHub returned invalid SSH key inventory JSON.")
        return None
    if not isinstance(keys, list):
        diagnostic("GitHub returned an unexpected SSH key inventory.")
        return None
    return keys


def _observe(private_key, public_key):
    state, identity = _local_key(private_key, public_key)
    if state != "current":
        return state, identity, []

    keys = _remote_keys()
    if keys is None:
        return "blocked", identity, []
    registered = any(
        _public_identity(str(item.get("key", ""))) == identity for item in keys
    )
    return ("current" if registered else "drifted"), identity, keys


def _generate_key(private_key, title):
    private_key.parent.mkdir(parents=True, exist_ok=True)
    if os.name != "nt":
        os.chmod(private_key.parent, 0o700)
    result = capture(
        [
            "ssh-keygen",
            "-q",
            "-t",
            "ed25519",
            "-N",
            "",
            "-C",
            title,
            "-f",
            str(private_key),
        ]
    )
    if result.returncode != 0:
        report(result)
        return False
    if os.name != "nt":
        os.chmod(private_key, 0o600)
        os.chmod(Path(str(private_key) + ".pub"), 0o644)
    return True


def _upload_key(public_key, title):
    result = capture(
        [
            "gh",
            "ssh-key",
            "add",
            str(public_key),
            "--title",
            title,
            "--type",
            "authentication",
        ]
    )
    report(result)
    return result.returncode == 0


def _verify_key(private_key):
    result = capture(
        [
            "ssh",
            "-T",
            "-o",
            "BatchMode=yes",
            "-o",
            "ConnectTimeout=10",
            "-o",
            "ConnectionAttempts=1",
            "-o",
            "IdentitiesOnly=yes",
            "-o",
            "PermitLocalCommand=no",
            "-i",
            str(private_key),
            HOSTNAME,
        ]
    )
    if "successfully authenticated" in "\n".join(
        (result.stdout, result.stderr)
    ).lower():
        return True
    report(result)
    return False


def _delete_stale_keys(keys, identity, title):
    for item in keys:
        if item.get("title") != title:
            continue
        if _public_identity(str(item.get("key", ""))) == identity:
            continue
        result = capture(
            [
                "gh",
                "api",
                "--method",
                "DELETE",
                "/user/keys/{}".format(item["id"]),
            ]
        )
        if result.returncode != 0:
            report(result)
            return False
    return True


def github_ssh_key(operation, requested_version):
    if requested_version:
        raise InstallerError("GitHub SSH key management does not accept a requested version.")

    machine_id = _machine_id()
    missing = [
        name for name in ("gh", "ssh", "ssh-keygen") if shutil.which(name) is None
    ]
    if machine_id is None or missing:
        if missing:
            diagnostic("Missing required commands: {}".format(", ".join(missing)))
        return "blocked"

    private_key, public_key = _key_paths()
    title = "dotfiles:{}".format(machine_id)
    state, identity, keys = _observe(private_key, public_key)
    if operation == "status" or state == "blocked":
        return state
    if state == "current" and operation == "apply":
        return state
    if state == "drifted" and identity is None:
        return state

    if state == "absent":
        if not _generate_key(private_key, title):
            return "blocked"
        local_state, identity = _local_key(private_key, public_key)
        if local_state != "current":
            return local_state
        keys = _remote_keys()
        if keys is None:
            return "blocked"

    registered = any(
        _public_identity(str(item.get("key", ""))) == identity for item in keys
    )
    if not registered and not _upload_key(public_key, title):
        return "blocked"
    if not _verify_key(private_key):
        diagnostic("The managed GitHub SSH key did not pass authentication verification.")
        return "blocked"
    if operation == "upgrade" and not _delete_stale_keys(keys, identity, title):
        return "drifted"

    final_state, _, _ = _observe(private_key, public_key)
    return final_state


if __name__ == "__main__":
    raise SystemExit(main(github_ssh_key))
