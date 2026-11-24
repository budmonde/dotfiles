import argparse
import shutil
import subprocess
import sys


def operating_system():
    if sys.platform.startswith("linux"):
        return "linux"
    return {"darwin": "macos", "win32": "windows"}.get(sys.platform, sys.platform)


def noninteractive_sudo_available():
    if not shutil.which("sudo"):
        return False
    try:
        return subprocess.run(
            ["sudo", "-n", "true"],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=5,
            check=False,
        ).returncode == 0
    except (OSError, subprocess.TimeoutExpired):
        return False


def main():
    parser = argparse.ArgumentParser(description="Report a host fact for recipe selection.")
    parser.add_argument("fact", choices=["os", "noninteractive-sudo"])
    fact = parser.parse_args().fact
    if fact == "os":
        value = operating_system()
    else:
        value = "available" if noninteractive_sudo_available() else "unavailable"
    print(value)


if __name__ == "__main__":
    main()
