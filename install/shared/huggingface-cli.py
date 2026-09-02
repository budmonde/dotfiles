import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(os.environ["DOTBOT_INSTALL_REPO_ROOT"]) / "install/lib/python"))

from lifecycle import main, uv_tool


raise SystemExit(main(lambda operation, version: uv_tool("hf", "hf", operation, version)))
