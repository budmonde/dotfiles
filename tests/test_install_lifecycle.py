import contextlib
import importlib.util
import io
import re
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest import mock


REPO_ROOT = Path(__file__).resolve().parents[1]
LIFECYCLE_PATH = REPO_ROOT / "install/lib/python/lifecycle.py"
SPEC = importlib.util.spec_from_file_location("install_lifecycle", LIFECYCLE_PATH)
LIFECYCLE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(LIFECYCLE)


def completed(arguments):
    return subprocess.CompletedProcess(arguments, 0, stdout="", stderr="")


class MainTests(unittest.TestCase):
    def test_main_prints_one_valid_state(self):
        stdout = io.StringIO()
        with contextlib.redirect_stdout(stdout):
            result = LIFECYCLE.main(lambda operation, version: "current", ["status"])

        self.assertEqual(result, 0)
        self.assertEqual(stdout.getvalue(), "current\n")

    def test_main_rejects_requested_version_for_apply(self):
        handler = mock.Mock(return_value="current")
        stderr = io.StringIO()
        with contextlib.redirect_stderr(stderr):
            result = LIFECYCLE.main(handler, ["apply", "1.2.3"])

        self.assertEqual(result, 2)
        self.assertFalse(handler.called)

    def test_main_rejects_an_invalid_state(self):
        stderr = io.StringIO()
        with contextlib.redirect_stderr(stderr):
            result = LIFECYCLE.main(lambda operation, version: "installed", ["status"])

        self.assertEqual(result, 1)


class NpmProjectTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.project = Path(self.temporary.name)
        (self.project / "package.json").write_text('{"dependencies": {}}\n', encoding="utf-8")
        (self.project / "package-lock.json").write_text('{"lockfileVersion": 3}\n', encoding="utf-8")
        (self.project / "node_modules").mkdir()

    def tearDown(self):
        self.temporary.cleanup()

    def test_state_detects_lockfile_drift(self):
        with mock.patch.object(LIFECYCLE, "capture", side_effect=lambda arguments, cwd=None: completed(arguments)):
            self.assertEqual(LIFECYCLE._npm_project_state("npm", self.project), "drifted")
            LIFECYCLE._write_npm_project_stamp(self.project)
            self.assertEqual(LIFECYCLE._npm_project_state("npm", self.project), "current")
            (self.project / "package-lock.json").write_text('{"lockfileVersion": 2}\n', encoding="utf-8")
            self.assertEqual(LIFECYCLE._npm_project_state("npm", self.project), "drifted")

    def test_apply_converges_and_stamps_the_manifest(self):
        calls = []

        def capture(arguments, cwd=None):
            calls.append(list(arguments))
            return completed(arguments)

        with mock.patch.object(LIFECYCLE.shutil, "which", return_value="npm"), mock.patch.object(
            LIFECYCLE, "capture", side_effect=capture
        ):
            state = LIFECYCLE.npm_project(self.project, "apply")

        self.assertEqual(state, "current")
        self.assertTrue(any(arguments[1] == "install" for arguments in calls))
        self.assertTrue(LIFECYCLE._npm_project_stamp_matches(self.project))

    def test_apply_skips_a_current_project(self):
        LIFECYCLE._write_npm_project_stamp(self.project)
        calls = []

        def capture(arguments, cwd=None):
            calls.append(list(arguments))
            return completed(arguments)

        with mock.patch.object(LIFECYCLE.shutil, "which", return_value="npm"), mock.patch.object(
            LIFECYCLE, "capture", side_effect=capture
        ):
            state = LIFECYCLE.npm_project(self.project, "apply")

        self.assertEqual(state, "current")
        self.assertFalse(any(arguments[1] == "install" for arguments in calls))


class NpmGlobalTests(unittest.TestCase):
    def test_apply_reports_an_update_without_installing_it(self):
        with mock.patch.object(LIFECYCLE.shutil, "which", return_value="npm"), mock.patch.object(
            LIFECYCLE, "_npm_installed_version", return_value="1.0.0"
        ), mock.patch.object(
            LIFECYCLE, "_npm_state", return_value="update-available"
        ), mock.patch.object(LIFECYCLE, "capture") as capture:
            state = LIFECYCLE.npm_global("example-package", "apply")

        self.assertEqual(state, "update-available")
        capture.assert_not_called()


class ManifestTests(unittest.TestCase):
    def manifests(self):
        return [
            REPO_ROOT / "install.conf.yaml",
            REPO_ROOT / "install.unix.conf.yaml",
            REPO_ROOT / "install.windows.conf.yaml",
            *sorted((REPO_ROOT / "profiles").rglob("*.conf.yaml")),
        ]

    def references(self):
        references = []
        for manifest in self.manifests():
            for line in manifest.read_text(encoding="utf-8").splitlines():
                stripped = line.strip()
                if stripped.startswith("- install:"):
                    self.assertEqual(stripped, "- install:", (manifest, stripped))
                elif stripped.startswith("- install/"):
                    self.fail(
                        "{} must use [installer path, description] entries: {}".format(
                            manifest, stripped
                        )
                    )
                elif stripped.startswith("- [install/"):
                    match = re.fullmatch(r"- \[(install/[^,\]]+), (\S(?:.*\S)?)\]", stripped)
                    self.assertIsNotNone(match, (manifest, stripped))
                    references.append((manifest, match.group(1)))
        return references

    def test_every_directive_resolves_inside_the_repository(self):
        for manifest, reference in self.references():
            path = (REPO_ROOT / reference).resolve()
            try:
                path.relative_to(REPO_ROOT.resolve())
            except ValueError:
                self.fail((manifest, reference))
            self.assertTrue(path.is_file(), (manifest, reference))

    def test_platform_manifests_only_use_compatible_installers(self):
        for manifest, reference in self.references():
            relative_manifest = manifest.relative_to(REPO_ROOT).as_posix()
            if relative_manifest == "install.unix.conf.yaml" or relative_manifest.startswith("profiles/unix/"):
                self.assertTrue(reference.startswith(("install/unix/", "install/shared/")))
            if relative_manifest == "install.windows.conf.yaml" or relative_manifest.startswith("profiles/windows/"):
                self.assertTrue(reference.startswith(("install/windows/", "install/shared/")))

    def test_every_resource_installer_is_referenced(self):
        resource_installers = {
            path.relative_to(REPO_ROOT).as_posix()
            for root, pattern in (
                (REPO_ROOT / "install/shared", "*.py"),
                (REPO_ROOT / "install/unix", "*"),
                (REPO_ROOT / "install/windows", "*.ps1"),
            )
            for path in root.rglob(pattern)
            if path.is_file()
        }
        references = {reference for _, reference in self.references()}
        self.assertEqual(resource_installers - references, set())


if __name__ == "__main__":
    unittest.main()
