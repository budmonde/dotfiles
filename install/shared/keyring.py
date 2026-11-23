import os
import sys
from pathlib import Path


repo_root = Path(
    os.environ.get("DOTBOT_INSTALL_REPO_ROOT", Path(__file__).resolve().parents[2])
)
sys.path.insert(0, str(repo_root / "install/lib/python"))

from lifecycle import InstallerError, diagnostic, main
from lifecycle.keyring import check_keyring_write, keyring_ready


def keyring(operation, requested_version):
    if requested_version:
        raise InstallerError("The OS keyring recipe does not accept a requested version.")

    if not keyring_ready():
        return "blocked"
    if operation != "status" and not check_keyring_write():
        diagnostic("Unable to write, read, and remove a disposable item in the OS keyring.")
        return "blocked"
    return "current"


if __name__ == "__main__":
    raise SystemExit(main(keyring))
