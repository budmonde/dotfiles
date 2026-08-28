import json
import os
import shutil
import subprocess
import sys
from pathlib import Path


repo_root = Path(
    os.environ.get("DOTBOT_INSTALL_REPO_ROOT", Path(__file__).resolve().parents[2])
)
sys.path.insert(0, str(repo_root / "install/lib/python"))

from lifecycle import InstallerError, diagnostic, main


lockfile = repo_root / "config/nvim/lazy-lock.json"


def run(arguments, cwd=None):
    return subprocess.run(
        arguments,
        cwd=str(cwd) if cwd else None,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        encoding="utf-8",
        errors="replace",
        check=False,
    )


def nvim_data_root(nvim):
    result = run(
        [
            nvim,
            "--clean",
            "--headless",
            "-u",
            "NONE",
            "-i",
            "NONE",
            "--cmd",
            "lua io.write(vim.fn.stdpath('data'))",
            "--cmd",
            "qa",
        ]
    )
    if result.returncode != 0 or not result.stdout.strip():
        raise InstallerError("Could not determine Neovim's data directory")
    return Path(result.stdout.strip())


def locked_plugins():
    if not lockfile.is_file():
        raise InstallerError("Missing Neovim plugin lockfile: {}".format(lockfile))
    payload = json.loads(lockfile.read_text(encoding="utf-8"))
    plugins = {}
    for name, metadata in payload.items():
        commit = metadata.get("commit") if isinstance(metadata, dict) else None
        if not isinstance(commit, str) or not commit:
            raise InstallerError("Neovim lock entry {} has no commit".format(name))
        plugins[name] = commit
    return plugins


def plugin_mismatches(nvim):
    plugin_root = nvim_data_root(nvim) / "lazy"
    mismatches = []
    for name, expected in locked_plugins().items():
        directory = plugin_root / name
        if not directory.is_dir():
            mismatches.append("{} is missing".format(name))
            continue
        result = run(["git", "rev-parse", "HEAD"], cwd=directory)
        actual = result.stdout.strip() if result.returncode == 0 else ""
        if actual != expected:
            mismatches.append("{} is at {}, expected {}".format(name, actual or "unknown", expected))
    return mismatches


def state(nvim):
    mismatches = plugin_mismatches(nvim)
    for mismatch in mismatches:
        diagnostic(mismatch)
    return "drifted" if mismatches else "current"


def invoke_lazy(nvim, command):
    result = run([nvim, "--headless", "+Lazy! {}".format(command), "+qa"])
    for output in (result.stdout, result.stderr):
        for line in output.splitlines():
            if line.strip():
                diagnostic(line)
    if result.returncode != 0:
        raise InstallerError("Neovim Lazy {} failed".format(command))


def handle(operation, requested_version):
    if requested_version:
        raise InstallerError("Neovim plugin state does not accept a requested version")
    nvim = shutil.which("nvim")
    if nvim is None:
        return "blocked"
    current_state = state(nvim)
    if operation == "status" or operation == "apply" and current_state == "current":
        return current_state
    invoke_lazy(nvim, "restore" if operation == "apply" else "update")
    final_state = state(nvim)
    if final_state != "current":
        raise InstallerError("Neovim plugins still differ from lazy-lock.json")
    return final_state


raise SystemExit(main(handle))
