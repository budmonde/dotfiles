import os
import sys
from pathlib import Path

repo_root = Path(os.environ["DOTBOT_INSTALL_REPO_ROOT"])
sys.path.insert(0, str(repo_root / "install/lib/python"))

from lifecycle import main, npm_project


project = repo_root / "config/agents/plugins/git-auditor"
raise SystemExit(main(lambda operation, version: npm_project(project, operation, version)))
