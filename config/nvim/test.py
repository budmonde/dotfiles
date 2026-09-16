import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path


def main():
    nvim = shutil.which("nvim")
    if nvim is None:
        print("Neovim is not installed", file=sys.stderr)
        return 1

    nvim_root = Path(__file__).resolve().parent
    tests = sorted((nvim_root / "tests").glob("*.test.lua"))
    with tempfile.TemporaryDirectory() as state_home:
        environment = os.environ.copy()
        environment["XDG_STATE_HOME"] = state_home
        for test in tests:
            result = subprocess.run(
                [nvim, "--headless", "-i", "NONE", "-u", "NONE", "-l", str(test)],
                cwd=nvim_root,
                env=environment,
            )
            if result.returncode != 0:
                return result.returncode
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
