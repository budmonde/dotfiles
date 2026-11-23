import getpass
import os
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path


sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "lib/python"))
from lifecycle import diagnostic
from lifecycle.keyring import linux_keyring_command, linux_keyring_ready


def _shell(arguments):
    if arguments:
        return subprocess.call(arguments)
    return subprocess.call([os.environ.get("SHELL") or "/bin/bash", "-i"])


def _start_keyring(arguments):
    daemon, environment = linux_keyring_command("gnome-keyring-daemon")
    if not daemon:
        diagnostic("Install GNOME Keyring before starting a private keyring session.")
        return 1

    with tempfile.TemporaryDirectory(prefix="dotfiles-keyring-session-") as directory:
        # The inherited GNOME socket can belong to a different D-Bus session.
        environment["GNOME_KEYRING_CONTROL"] = directory
        password = getpass.getpass("GNOME Keyring passphrase: ")
        result = subprocess.run(
            [
                daemon,
                "--unlock",
                "--components=secrets",
                "--control-directory=" + directory,
            ],
            # EOF means no passphrase was supplied. A NUL supplies an empty passphrase.
            input=password or "\0",
            text=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=15,
            env=environment,
        )
        del password
        if result.returncode == 0:
            for _ in range(6):
                if linux_keyring_ready():
                    return _shell(arguments)
                time.sleep(0.2)
        diagnostic("Could not unlock the default Secret Service collection in the new session.")
        return 1


def main(arguments):
    if arguments in (["--help"], ["-h"]):
        print("Usage: python3 install/unix/keyring-session.py [-- COMMAND [ARG ...]]")
        print("Open a shell or run a command in a Linux session with an unlocked keyring.")
        return 0
    if not sys.platform.startswith("linux"):
        diagnostic("This launcher is for Linux. Use the native user keyring on this platform.")
        return 1
    if arguments[:1] == ["--new-bus"]:
        return _start_keyring(arguments[1:])
    if arguments and arguments[0] != "--":
        diagnostic("Use -- before the command to run. See --help.")
        return 2
    command = arguments[1:]
    if linux_keyring_ready():
        return _shell(command)
    if not sys.stdin.isatty() or not shutil.which("dbus-run-session") or not shutil.which("dbus-send"):
        diagnostic("Keyring setup needs a terminal and the dbus-run-session and dbus-send commands.")
        return 1
    return subprocess.call([
        "dbus-run-session", "--", sys.executable, str(Path(__file__).resolve()), "--new-bus", *command
    ])


if __name__ == "__main__":
    try:
        raise SystemExit(main(sys.argv[1:]))
    except (EOFError, OSError, subprocess.TimeoutExpired):
        diagnostic("Could not start or unlock the Linux keyring session.")
        raise SystemExit(1)
