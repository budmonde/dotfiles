import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(os.environ["DOTBOT_INSTALL_REPO_ROOT"]) / "install/lib/python"))

from lifecycle import main, npm_global


raise SystemExit(main(lambda operation, version: npm_global("@anthropic-ai/claude-code", operation, version)))
