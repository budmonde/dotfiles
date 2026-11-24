import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(os.environ["DOTBOT_INSTALL_REPO_ROOT"]) / "install/lib"))

from lifecycle.python import core, npm


def main(arguments):
    package, *arguments = arguments
    version = None
    if arguments[:1] == ["--version"]:
        if len(arguments) < 2:
            raise SystemExit("--version requires a value")
        version = arguments[1]
        arguments = arguments[2:]
    if len(arguments) != 1:
        raise SystemExit("expected PACKAGE [--version VERSION] OPERATION")

    def install(operation, requested_version):
        return npm.global_package(package, operation=operation, requested_version=requested_version)

    protocol_arguments = arguments + ([version] if version else [])
    return core.main(install, protocol_arguments)


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
