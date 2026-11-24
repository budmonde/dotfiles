import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(os.environ["DOTBOT_INSTALL_REPO_ROOT"]) / "install/lib"))

from lifecycle.python import core, uv


def install(operation, requested_version):
    return uv.tool("hf", "hf", operation=operation, requested_version=requested_version)


if __name__ == "__main__":
    raise SystemExit(core.main(install))
