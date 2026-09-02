import os
import subprocess
import sys
from pathlib import Path
from typing import Callable, List, Optional, Sequence


Handler = Callable[[str, str], str]

STATES = {
    "absent",
    "blocked",
    "current",
    "drifted",
    "unsupported",
    "update-available",
}


class InstallerError(RuntimeError):
    pass


def diagnostic(message: str) -> None:
    print(message, file=sys.stderr)


def online_allowed() -> bool:
    return os.environ.get("DOTBOT_INSTALL_ONLINE", "1").strip().lower() not in {
        "0",
        "false",
        "no",
        "off",
    }


def capture(
    arguments: Sequence[str], cwd: Optional[Path] = None
) -> subprocess.CompletedProcess:
    return subprocess.run(
        list(arguments),
        cwd=str(cwd) if cwd else None,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        encoding="utf-8",
        errors="replace",
        check=False,
    )


def report(result: subprocess.CompletedProcess) -> None:
    for output in (result.stdout, result.stderr):
        for line in output.splitlines():
            if line.strip():
                diagnostic(line)


def main(handler: Handler, arguments: Optional[List[str]] = None) -> int:
    values = list(sys.argv[1:] if arguments is None else arguments)
    if not values or len(values) > 2:
        diagnostic("Expected: <status|apply|upgrade> [requested-version]")
        return 2
    operation = values[0]
    requested_version = values[1] if len(values) == 2 else ""
    if operation not in {"status", "apply", "upgrade"}:
        diagnostic("Unsupported installer operation: {}".format(operation))
        return 2
    try:
        state = handler(operation, requested_version)
    except (InstallerError, OSError, ValueError) as error:
        diagnostic(str(error))
        return 1
    if state not in STATES:
        diagnostic("Installer returned an invalid state: {}".format(state))
        return 1
    print(state)
    return 0
