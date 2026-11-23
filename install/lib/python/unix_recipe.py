import platform
import shutil
import subprocess
import sys


UNIX_BRANCHES = ("macos", "linux", "wsl", "linux-userspace")


def platform_recipe_files(directory):
    yield from sorted(directory.glob("*.conf.yaml"))
    if directory.name == "unix":
        for branch in UNIX_BRANCHES:
            yield from sorted((directory / branch).glob("*.conf.yaml"))


def unix_recipe_fragment(platform_file):
    unix_directory = platform_file.parent
    if unix_directory.name != "unix":
        return platform_file
    if not any(
        (unix_directory / branch / platform_file.name).is_file() for branch in UNIX_BRANCHES
    ):
        return platform_file

    branch = unix_recipe_branch()
    if branch is None:
        return platform_file
    variant = unix_directory / branch / platform_file.name
    return variant if variant.is_file() else platform_file


def unix_recipe_branch():
    if sys.platform == "darwin":
        return "macos"
    if sys.platform.startswith("linux"):
        if not system_packages_available():
            return "linux-userspace"
        if "microsoft" in platform.release().lower():
            return "wsl"
        return "linux"


def system_packages_available():
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
