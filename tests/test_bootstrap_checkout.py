import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


BOOTSTRAP = Path(__file__).resolve().parents[1] / "bootstrap" / "checkout.py"
PUBLIC_URL = "https://github.com/budmonde/dotfiles.git"


class WorkspaceBootstrapTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="dotfiles bootstrap ")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.public = self.root / "public"
        self.personal = self.root / "personal"
        self.extension = self.root / "extension"
        self.workspace = self.root / "dotfiles"
        self.environment = {
            **os.environ,
            "GIT_CONFIG_NOSYSTEM": "1",
            "GIT_CONFIG_GLOBAL": os.devnull,
            "GIT_ALLOW_PROTOCOL": "file",
            "GIT_AUTHOR_NAME": "Bootstrap Fixture",
            "GIT_AUTHOR_EMAIL": "fixture@example.invalid",
            "GIT_COMMITTER_NAME": "Bootstrap Fixture",
            "GIT_COMMITTER_EMAIL": "fixture@example.invalid",
            "GIT_CONFIG_COUNT": "1",
            "GIT_CONFIG_KEY_0": f"url.{self.public.as_uri()}.insteadOf",
            "GIT_CONFIG_VALUE_0": PUBLIC_URL,
        }

        self.git(self.root, "init", "-b", "main", str(self.public))
        self.write(self.public, "config/profile", "public config\n")
        self.write(self.public, ".gitignore", ".install-recipes\n")
        self.commit(self.public)

        self.git(self.root, "clone", str(self.public), str(self.personal))
        self.write(self.personal, "AGENTS.md", "personal setup\n")
        self.commit(self.personal)

        self.git(self.root, "clone", str(self.personal), str(self.extension))
        self.git(self.extension, "branch", "-m", "extension-main")
        self.write(self.extension, "config/profile", "extended config\n")
        self.commit(self.extension)

        self.git(self.root, "clone", PUBLIC_URL, str(self.workspace))
        self.write(self.workspace, ".install-recipes", "00-base\n")

    def git(self, directory, *arguments):
        return subprocess.run(
            ["git", "-C", str(directory), *arguments],
            env=self.environment,
            capture_output=True,
            text=True,
            check=True,
        ).stdout.strip()

    def write(self, directory, name, contents):
        path = directory / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(contents, encoding="utf-8")

    def commit(self, directory):
        self.git(directory, "add", ".")
        self.git(directory, "commit", "-m", "Build fixture")

    def bootstrap(self, stage="private", *, success=True):
        manifest = self.root / f"{stage}.json"
        source, remote, url, upstream = (
            ("public", "origin", self.personal, "main") if stage == "private"
            else ("private", "extended", self.extension, "extension-main")
        )
        manifest.write_text(json.dumps({
            "from": source, "remote": remote, "url": str(url),
            "branch": upstream, "checkout": stage,
        }), encoding="utf-8")
        result = subprocess.run(
            [sys.executable, str(BOOTSTRAP), "--workspace", str(self.workspace),
             str(manifest)],
            env=self.environment, capture_output=True, text=True,
        )
        if success:
            self.assertEqual(result.returncode, 0, result.stderr)
        else:
            self.assertNotEqual(result.returncode, 0, result.stdout)
        return result

    def test_adds_tracking_branches_and_checks_out_extended(self):
        self.bootstrap()
        self.bootstrap("extended")
        for local, upstream in (
            ("public", "public/main"),
            ("private", "origin/main"),
            ("extended", "extended/extension-main"),
        ):
            self.assertEqual(
                self.git(self.workspace, "rev-parse", "--abbrev-ref", f"{local}@{{upstream}}"),
                upstream,
            )
        self.assertEqual(self.git(self.workspace, "branch", "--show-current"), "extended")
        self.assertEqual((self.workspace / "config/profile").read_text(), "extended config\n")
        self.assertEqual((self.workspace / ".install-recipes").read_text(), "00-base\n")
        self.assertEqual(self.git(self.workspace, "status", "--porcelain"), "")

    def test_personal_only_setup_can_add_extended_later_and_retry(self):
        self.bootstrap()
        self.assertEqual(self.git(self.workspace, "branch", "--show-current"), "private")
        self.assertNotIn("extended", self.git(self.workspace, "remote").splitlines())

        self.bootstrap("extended")
        self.bootstrap("extended")
        self.assertEqual(self.git(self.workspace, "branch", "--show-current"), "extended")

    def test_failed_extended_fetch_keeps_private_checkout_and_can_retry(self):
        self.bootstrap()
        unavailable = self.extension.with_name("extension offline")
        self.extension.rename(unavailable)
        try:
            self.bootstrap("extended", success=False)
            self.assertEqual(self.git(self.workspace, "branch", "--show-current"), "private")
            self.assertEqual((self.workspace / "config/profile").read_text(), "public config\n")
        finally:
            unavailable.rename(self.extension)

        self.bootstrap("extended")
        self.assertEqual(self.git(self.workspace, "branch", "--show-current"), "extended")

    def test_extended_cannot_skip_private(self):
        self.assertIn("Run this stage from private", self.bootstrap("extended", success=False).stderr)
        self.assertEqual(self.git(self.workspace, "branch", "--show-current"), "main")
        self.assertEqual(self.git(self.workspace, "remote"), "origin")

    def test_checkout_preserves_existing_files_on_collision(self):
        self.write(self.workspace, "AGENTS.md", "untracked instructions\n")
        self.bootstrap(success=False)
        self.assertEqual((self.workspace / "AGENTS.md").read_text(), "untracked instructions\n")
        self.assertEqual(self.git(self.workspace, "branch", "--show-current"), "public")


if __name__ == "__main__":
    unittest.main()
