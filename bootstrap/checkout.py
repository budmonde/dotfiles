"""Fetch and check out the next dotfiles layer from a bootstrap manifest."""

import argparse
import json
import subprocess
import sys
from pathlib import Path


PUBLIC_URLS = {
    "https://github.com/budmonde/dotfiles",
    "ssh://git@github.com/budmonde/dotfiles",
    "git@github.com:budmonde/dotfiles",
}


def checkout(workspace, manifest):
    def git(*args, capture=False):
        result = subprocess.run(
            ["git", "-C", str(workspace), *args],
            check=True, text=True, stdout=subprocess.PIPE if capture else None,
        )
        return result.stdout.strip() if capture else None

    current = git("branch", "--show-current", capture=True)
    source, remote, url, upstream, target = (
        manifest[key] for key in ("from", "remote", "url", "branch", "checkout")
    )
    if current not in {source, target} and (source, current) != ("public", "main"):
        raise ValueError(f"Run this stage from {source} or {target}.")
    if git("status", "--porcelain", "--untracked-files=no", capture=True):
        raise ValueError("Commit or set aside tracked changes before switching dotfiles layers.")

    remotes = set(git("remote", capture=True).splitlines())
    if current == "main" and source == "public":
        public_remote = "public" if "public" in remotes else "origin"
        public_url = git("config", "--local", "--get", f"remote.{public_remote}.url", capture=True)
        if public_url.rstrip("/").removesuffix(".git") not in PUBLIC_URLS:
            raise ValueError("The main branch must be from the public dotfiles repository.")
        if public_remote == "origin":
            git("remote", "rename", "origin", "public")
            remotes.remove("origin")
            remotes.add("public")
        git("branch", "-m", "public")

    if remote not in remotes:
        git("remote", "add", "-t", upstream, "--", remote, url)
    elif git("config", "--local", "--get", f"remote.{remote}.url", capture=True) != url:
        raise ValueError(f"The configured {remote} remote uses a different URL.")

    reference = f"refs/remotes/{remote}/{upstream}"
    git("fetch", "--no-tags", "--no-recurse-submodules", remote, f"refs/heads/{upstream}:{reference}")
    branches = git("for-each-ref", "--format=%(refname:lstrip=2)", "refs/heads", capture=True).splitlines()
    if target not in branches:
        git("branch", "--track", target, reference)
    git("checkout", "--no-recurse-submodules", "--no-overwrite-ignore", target)
    git("-c", "submodule.recurse=false", "merge", "--ff-only", "--no-overwrite-ignore", reference)
    git("branch", "--set-upstream-to", reference, target)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("manifest", help="JSON file defining the next layer, or - for standard input")
    parser.add_argument("--workspace", type=Path, default=Path.cwd(), help="dotfiles checkout (default: current directory)")
    arguments = parser.parse_args()
    try:
        contents = sys.stdin.read() if arguments.manifest == "-" else Path(arguments.manifest).read_text(encoding="utf-8-sig")
        manifest = json.loads(contents)
        fields = {"from", "remote", "url", "branch", "checkout"}
        if not isinstance(manifest, dict) or manifest.keys() != fields or any(
            not isinstance(value, str) or not value.strip() or value.startswith("-")
            for value in manifest.values()
        ):
            raise ValueError("Manifest must define from, remote, url, branch, and checkout.")
        checkout(arguments.workspace, manifest)
    except subprocess.CalledProcessError as error:
        return error.returncode
    except (ValueError, OSError) as error:
        print(f"dotfiles bootstrap: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
