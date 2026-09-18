import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(os.environ["DOTBOT_INSTALL_REPO_ROOT"]) / "install/lib/python"))

from lifecycle import main, npm_global


package, *arguments = sys.argv[1:]
version = None
if arguments[:1] == ["--version"]:
    if len(arguments) < 2:
        raise SystemExit("--version requires a value")
    version = arguments[1]
    arguments = arguments[2:]
if len(arguments) != 1:
    raise SystemExit("expected PACKAGE [--version VERSION] OPERATION")

operation = arguments[0]
protocol_arguments = [operation] + ([version] if version else [])
raise SystemExit(main(lambda selected, desired: npm_global(package, selected, desired), protocol_arguments))
