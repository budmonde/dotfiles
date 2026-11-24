import json
import os
import platform
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path


repo_root = Path(
    os.environ.get("DOTBOT_INSTALL_REPO_ROOT", Path(__file__).resolve().parents[2])
)
sys.path.insert(0, str(repo_root / "install/lib"))

from lifecycle.python.core import InstallerError, diagnostic, main
from lifecycle.python.core import capture


minimum_version = (2, 36, 0)


def version(binary):
    result = capture([str(binary), "--version"])
    match = re.match(r"git version (\d+)\.(\d+)\.(\d+)", result.stdout)
    if result.returncode or match is None:
        return ()
    return tuple(map(int, match.groups()))


def paths():
    data = Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share"))
    return data / "git-install", Path.home() / ".local/bin/git"


def state():
    if platform.system() != "Linux":
        return "unsupported"
    installation, link = paths()
    if link.is_symlink() and link.resolve() == installation / "bin/git":
        if not link.exists() or version(link) < minimum_version:
            return "drifted"
        return "current"
    candidate = str(link) if link.exists() else shutil.which("git")
    if candidate and version(candidate) >= minimum_version:
        return "current"
    if link.exists() or link.is_symlink():
        diagnostic("Refusing to replace an unmanaged {}".format(link))
        return "blocked"
    return "drifted" if candidate else "absent"


def run(arguments, cwd=None):
    result = subprocess.run(
        list(map(str, arguments)),
        cwd=cwd,
        stdin=subprocess.DEVNULL,
        stdout=sys.stderr,
        stderr=sys.stderr,
        check=False,
    )
    if result.returncode:
        raise InstallerError("Git installation failed: {}".format(arguments[0]))


def latest_version():
    result = capture([
        "curl", "-fsSL", "--max-time", "60",
        "https://api.github.com/repos/git/git/tags?per_page=100",
    ])
    if result.returncode:
        raise InstallerError("Could not resolve the latest stable Git tag")
    tags = json.loads(result.stdout)
    versions = [
        tuple(map(int, match.groups()))
        for tag in tags
        for match in [re.fullmatch(r"v(\d+)\.(\d+)\.(\d+)", tag["name"])]
        if match
    ]
    if not versions or max(versions) < minimum_version:
        raise InstallerError("No supported stable Git tag was found")
    return ".".join(map(str, max(versions)))


def install():
    installation, link = paths()
    if link.exists() or link.is_symlink():
        if not link.is_symlink() or link.resolve() != installation / "bin/git":
            raise InstallerError("Refusing to replace an unmanaged {}".format(link))
    if installation.is_symlink() or installation.exists() and not installation.is_dir():
        raise InstallerError("Refusing to replace {}".format(installation))
    missing = [tool for tool in ("cc", "make", "curl", "tar", "perl") if not shutil.which(tool)]
    if missing:
        diagnostic("Building Git requires: {}".format(", ".join(missing)))
        return "blocked"
    target = latest_version()
    diagnostic("Building Git {} locally; requires curl, OpenSSL, zlib and expat development libraries".format(target))
    installation.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=".git-build-", dir=installation.parent) as directory:
        temporary = Path(directory)
        archive = temporary / "git.tar.gz"
        run([
            "curl", "-fsSL", "--max-time", "300",
            "https://github.com/git/git/archive/refs/tags/v{}.tar.gz".format(target),
            "-o", archive,
        ])
        run(["tar", "-xzf", archive, "-C", temporary])
        source = temporary / "git-{}".format(target)
        arguments = [
            "make", "-j2", "prefix={}".format(installation),
            "NO_GETTEXT=YesPlease", "NO_TCLTK=YesPlease", "NO_RUST=YesPlease",
        ]
        run(arguments + ["all"], cwd=source)
        staging = temporary / "staging"
        run(arguments + ["DESTDIR={}".format(staging), "install"], cwd=source)
        payload = staging / installation.relative_to(installation.anchor)
        if version(payload / "bin/git") != tuple(map(int, target.split("."))):
            raise InstallerError("The staged Git binary did not report the expected version")
        backup = temporary / "previous"
        if installation.exists():
            installation.rename(backup)
        try:
            payload.rename(installation)
            helper = capture([str(installation / "bin/git"), "--exec-path"])
            if helper.returncode or not (Path(helper.stdout.strip()) / "git-remote-https").is_file():
                raise InstallerError("The installed Git HTTPS helper is missing")
            link.parent.mkdir(parents=True, exist_ok=True)
            replacement = temporary / "git-link"
            replacement.symlink_to(installation / "bin/git")
            replacement.replace(link)
        except BaseException:
            if installation.exists():
                shutil.rmtree(installation)
            if backup.exists():
                backup.rename(installation)
            raise
    return state()


def handle(operation, requested_version):
    if requested_version:
        raise InstallerError("The Git installer does not accept an exact version")
    observed = state()
    if operation == "status" or observed in {"unsupported", "blocked"}:
        return observed
    if operation == "apply" and observed == "current":
        return observed
    return install()


if __name__ == "__main__":
    raise SystemExit(main(handle))
