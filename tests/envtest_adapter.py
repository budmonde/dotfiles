# /// script
# requires-python = ">=3.8"
# dependencies = ["PyYAML>=6,<7"]
# ///

import os
import runpy
import sys


def main() -> None:
    os.environ["PATH"] = os.environ.pop("DOTFILES_ENVTEST_PATH")
    script = sys.argv.pop(1)
    runpy.run_path(script, run_name="__main__")


if __name__ == "__main__":
    main()
