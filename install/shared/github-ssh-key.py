import json
import os
import sys
from pathlib import Path


repo_root = Path(
    os.environ.get("DOTBOT_INSTALL_REPO_ROOT", Path(__file__).resolve().parents[2])
)
sys.path.insert(0, str(repo_root / "install/lib/python"))

from lifecycle import capture, diagnostic, main, managed_ssh_key, report


HOSTNAME = "github.com"


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


def _delete_key(key_id):
    result = capture(
        ["gh", "api", "--method", "DELETE", "/user/keys/{}".format(key_id)]
    )
    if result.returncode != 0:
        report(result)
        return False
    return True


def github_ssh_key(operation, requested_version):
    return managed_ssh_key(
        operation,
        requested_version,
        service_name="GitHub",
        key_filename="github_ed25519",
        required_commands=("gh", "ssh", "ssh-keygen"),
        ssh_target=HOSTNAME,
        authentication_text="successfully authenticated",
        list_remote_keys=_remote_keys,
        upload_remote_key=_upload_key,
        delete_remote_key=_delete_key,
    )


if __name__ == "__main__":
    raise SystemExit(main(github_ssh_key))
