import os
import sys
from pathlib import Path


repo_root = Path(
    os.environ.get("DOTBOT_INSTALL_REPO_ROOT", Path(__file__).resolve().parents[2])
)
sys.path.insert(0, str(repo_root / "install/lib"))

from lifecycle.python.core import InstallerError, diagnostic, main
from lifecycle.python.keyring import check_write, ready


def keyring(operation, requested_version):
    if requested_version:
        raise InstallerError("The OS keyring recipe does not accept a requested version.")

    if not ready():
        return "blocked"
    if operation != "status" and not check_write():
        diagnostic("Unable to write, read, and remove a disposable item in the OS keyring.")
        return "blocked"
    return "current"


if __name__ == "__main__":
    raise SystemExit(main(keyring))
