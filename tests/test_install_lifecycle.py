import contextlib
import importlib.util
import io
import os
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock


REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT / "install/lib"))
from lifecycle.python import core as CORE
from lifecycle.python import keyring as KEYRING
from lifecycle.python import npm as NPM
from lifecycle.python import ssh_key as SSH_KEY
from lifecycle.python import uv as UV
import recipe_resolver as RECIPE_RESOLVER

sys.path.insert(0, str(REPO_ROOT))
import orchestrate as ORCHESTRATE


def load_installer(module_name, filename):
    spec = importlib.util.spec_from_file_location(
        module_name, REPO_ROOT / "install/resources" / filename
    )
    module = importlib.util.module_from_spec(spec)
    with mock.patch.dict(os.environ, {"DOTBOT_INSTALL_REPO_ROOT": str(REPO_ROOT)}):
        spec.loader.exec_module(module)
    return module


GITHUB_AUTH = load_installer("github_auth_installer", "github-auth.py")
GITHUB_SSH_KEY = load_installer("github_ssh_key_installer", "github-ssh-key.py")
KEYRING_INSTALLER = load_installer("keyring_installer", "keyring.py")


def completed(arguments):
    return subprocess.CompletedProcess(arguments, 0, stdout="", stderr="")


class GitInstallerTests(unittest.TestCase):
    def setUp(self):
        spec = importlib.util.spec_from_file_location(
            "git_installer", REPO_ROOT / "install/resources/git.unix.py"
        )
        self.installer = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.installer)
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        root = Path(self.temporary.name)
        self.installation = root / "data/git-install"
        self.link = root / "bin/git"
        for patcher in (
            mock.patch.object(self.installer, "paths", return_value=(self.installation, self.link)),
            mock.patch.object(self.installer.platform, "system", return_value="Linux"),
        ):
            patcher.start()
            self.addCleanup(patcher.stop)

    def test_status_detects_old_git_without_mutating_or_contacting_upstream(self):
        with mock.patch.object(self.installer.shutil, "which", return_value="/usr/bin/git"), mock.patch.object(
            self.installer, "version", return_value=(2, 34, 1)
        ), mock.patch.object(self.installer, "latest_version") as latest:
            self.assertEqual(self.installer.handle("status", ""), "drifted")
        latest.assert_not_called()
        self.assertFalse(self.installation.parent.exists())

    def test_apply_preserves_acceptable_system_git_but_upgrade_installs(self):
        with mock.patch.object(self.installer.shutil, "which", return_value="/usr/bin/git"), mock.patch.object(
            self.installer, "version", return_value=(2, 43, 0)
        ), mock.patch.object(self.installer, "install", return_value="current") as install:
            self.assertEqual(self.installer.handle("apply", ""), "current")
            install.assert_not_called()
            self.assertEqual(self.installer.handle("upgrade", ""), "current")
            install.assert_called_once()

    def test_apply_repairs_old_system_git(self):
        with mock.patch.object(self.installer.shutil, "which", return_value="/usr/bin/git"), mock.patch.object(
            self.installer, "version", return_value=(2, 34, 1)
        ), mock.patch.object(self.installer, "install", return_value="current") as install:
            self.assertEqual(self.installer.handle("apply", ""), "current")
            install.assert_called_once()

    def test_broken_managed_link_is_repairable(self):
        self.link.parent.mkdir()
        self.link.symlink_to(self.installation / "bin/git")
        self.assertEqual(self.installer.handle("status", ""), "drifted")

    def test_unmanaged_old_local_git_is_preserved(self):
        self.link.parent.mkdir()
        self.link.write_text("external installation")
        with mock.patch.object(self.installer, "version", return_value=(2, 34, 1)), mock.patch.object(
            self.installer, "install"
        ) as install:
            self.assertEqual(self.installer.handle("apply", ""), "blocked")
        install.assert_not_called()
        self.assertEqual(self.link.read_text(), "external installation")

    def test_build_failure_preserves_existing_managed_git(self):
        (self.installation / "bin").mkdir(parents=True)
        (self.installation / "bin/git").write_text("previous installation")
        self.link.parent.mkdir()
        self.link.symlink_to(self.installation / "bin/git")
        with mock.patch.object(self.installer, "latest_version", return_value="2.56.0"), mock.patch.object(
            self.installer.shutil, "which", return_value="/usr/bin/tool"
        ), mock.patch.object(self.installer, "run", side_effect=CORE.InstallerError("build failed")):
            with self.assertRaises(CORE.InstallerError):
                self.installer.install()
        self.assertEqual(self.link.read_text(), "previous installation")
        self.assertEqual(list(self.installation.parent.iterdir()), [self.installation])

    def test_latest_version_excludes_release_candidates(self):
        response = subprocess.CompletedProcess([], 0, stdout='[{"name":"v2.57.0-rc0"},{"name":"v2.56.0"},{"name":"v2.9.5"}]')
        with mock.patch.object(self.installer, "capture", return_value=response):
            self.assertEqual(self.installer.latest_version(), "2.56.0")

    def test_failed_post_install_verification_restores_previous_git(self):
        (self.installation / "bin").mkdir(parents=True)
        (self.installation / "bin/git").write_text("previous installation")
        self.link.parent.mkdir()
        self.link.symlink_to(self.installation / "bin/git")

        def stage(arguments, cwd=None):
            if arguments[-1] == "install":
                staging = Path(next(value.split("=", 1)[1] for value in arguments if value.startswith("DESTDIR=")))
                payload = staging / self.installation.relative_to(self.installation.anchor)
                (payload / "bin").mkdir(parents=True)
                (payload / "bin/git").write_text("replacement installation")

        with mock.patch.object(self.installer, "latest_version", return_value="2.56.0"), mock.patch.object(
            self.installer.shutil, "which", return_value="/usr/bin/tool"
        ), mock.patch.object(self.installer, "run", side_effect=stage), mock.patch.object(
            self.installer, "version", return_value=(2, 56, 0)
        ), mock.patch.object(self.installer, "capture", return_value=subprocess.CompletedProcess([], 1, stdout="")):
            with self.assertRaisesRegex(CORE.InstallerError, "HTTPS helper"):
                self.installer.install()
        self.assertEqual(self.link.read_text(), "previous installation")
        self.assertEqual(list(self.installation.parent.iterdir()), [self.installation])


class WindowsEnvironmentBackendTests(unittest.TestCase):
    def run_lifecycle(self, script):
        if os.name != "nt":
            self.skipTest("Windows environment scopes require Windows")
        powershell = shutil.which("pwsh") or shutil.which("powershell")
        if powershell is None:
            self.skipTest("PowerShell is not available")
        module = str(REPO_ROOT / "install/lib/lifecycle/PowerShell.psm1").replace(
            "'", "''"
        )
        result = subprocess.run(
            [
                powershell,
                "-NoProfile",
                "-NonInteractive",
                "-Command",
                "Import-Module '{}' -Force; {}".format(module, script),
            ],
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        return result.stdout.strip().splitlines()

    def test_facade_exports_the_stable_windows_lifecycle_api(self):
        lines = self.run_lifecycle(
            "Get-Command -Module Lifecycle | Sort-Object Name | Select-Object -ExpandProperty Name"
        )

        self.assertEqual(
            lines,
            [
                "Get-WindowsEnvironmentVariable",
                "Get-WindowsEnvironmentVariableState",
                "Invoke-DotbotInstaller",
                "Invoke-PowerShellGalleryModule",
                "Invoke-WindowsEnvironmentVariable",
                "Invoke-WinGetPackage",
                "Restart-DotbotInstallerInPowerShellCore",
                "Send-WindowsEnvironmentChange",
                "Set-WindowsEnvironmentVariable",
                "Test-WindowsEnvironmentValue",
                "Write-DotbotInstallerDiagnostic",
            ],
        )

    def test_state_distinguishes_absent_current_and_drifted(self):
        lines = self.run_lifecycle(
            "$name = 'DOTFILES_LIFECYCLE_TEST_VALUE'; "
            "[Environment]::SetEnvironmentVariable($name, $null, 'Process'); "
            "Get-WindowsEnvironmentVariableState -Name $name -Value 'expected' -Scope Process; "
            "[Environment]::SetEnvironmentVariable($name, 'expected', 'Process'); "
            "Get-WindowsEnvironmentVariableState -Name $name -Value 'expected' -Scope Process; "
            "Get-WindowsEnvironmentVariableState -Name $name -Value 'other' -Scope Process"
        )

        self.assertEqual(lines, ["absent", "current", "drifted"])

    def test_apply_converges_and_reads_the_process_scope(self):
        lines = self.run_lifecycle(
            "$name = 'DOTFILES_LIFECYCLE_TEST_APPLY'; "
            "[Environment]::SetEnvironmentVariable($name, $null, 'Process'); "
            "$state = Invoke-WindowsEnvironmentVariable -Name $name -Value 'expected' "
            "-Scope Process -Operation apply; "
            "$actual = Get-WindowsEnvironmentVariable -Name $name -Scope Process; "
            'Write-Output "$state|$actual"'
        )

        self.assertEqual(lines, ["current|expected"])

    def test_status_is_read_only(self):
        lines = self.run_lifecycle(
            "$name = 'DOTFILES_LIFECYCLE_TEST_STATUS'; "
            "[Environment]::SetEnvironmentVariable($name, $null, 'Process'); "
            "$state = Invoke-WindowsEnvironmentVariable -Name $name -Value 'expected' "
            "-Scope Process -Operation status; "
            "$actual = Get-WindowsEnvironmentVariable -Name $name -Scope Process; "
            "if ([string]::IsNullOrEmpty($actual)) { $actual = '<absent>' }; "
            'Write-Output "$state|$actual"'
        )

        self.assertEqual(lines, ["absent|<absent>"])

    def test_path_state_normalizes_case_and_trailing_separator(self):
        lines = self.run_lifecycle(
            "$name = 'DOTFILES_LIFECYCLE_TEST_PATH'; "
            "$expected = Join-Path $env:TEMP 'DotfilesEnvironment'; "
            "$actual = $expected.ToUpperInvariant() + '\\'; "
            "[Environment]::SetEnvironmentVariable($name, $actual, 'Process'); "
            "Get-WindowsEnvironmentVariableState -Name $name -Value $expected -Scope Process -Path"
        )

        self.assertEqual(lines, ["current"])


class MainTests(unittest.TestCase):
    def test_main_prints_one_valid_state(self):
        stdout = io.StringIO()
        with contextlib.redirect_stdout(stdout):
            result = CORE.main(lambda operation, version: "current", ["status"])

        self.assertEqual(result, 0)
        self.assertEqual(stdout.getvalue(), "current\n")

    def test_main_passes_desired_version_for_apply(self):
        handler = mock.Mock(return_value="current")
        stdout = io.StringIO()

        with contextlib.redirect_stdout(stdout):
            result = CORE.main(handler, ["apply", "1.2.3"])

        self.assertEqual(result, 0)
        self.assertEqual(stdout.getvalue(), "current\n")
        handler.assert_called_once_with("apply", "1.2.3")

    def test_main_rejects_an_invalid_state(self):
        stderr = io.StringIO()
        with contextlib.redirect_stderr(stderr):
            result = CORE.main(lambda operation, version: "installed", ["status"])

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
        with mock.patch.object(
            NPM, "capture", side_effect=lambda arguments, cwd=None: completed(arguments)
        ):
            self.assertEqual(NPM._npm_project_state("npm", self.project), "drifted")
            NPM._write_npm_project_stamp(self.project)
            self.assertEqual(NPM._npm_project_state("npm", self.project), "current")
            (self.project / "package-lock.json").write_text('{"lockfileVersion": 2}\n', encoding="utf-8")
            self.assertEqual(NPM._npm_project_state("npm", self.project), "drifted")

    def test_apply_converges_and_stamps_the_manifest(self):
        calls = []

        def capture(arguments, cwd=None):
            calls.append(list(arguments))
            return completed(arguments)

        with mock.patch.object(NPM.shutil, "which", return_value="npm"), mock.patch.object(
            NPM, "capture", side_effect=capture
        ):
            state = NPM.project(self.project, operation="apply")

        self.assertEqual(state, "current")
        self.assertTrue(any(arguments[1] == "install" for arguments in calls))
        self.assertTrue(NPM._npm_project_stamp_matches(self.project))

    def test_apply_skips_a_current_project(self):
        NPM._write_npm_project_stamp(self.project)
        calls = []

        def capture(arguments, cwd=None):
            calls.append(list(arguments))
            return completed(arguments)

        with mock.patch.object(NPM.shutil, "which", return_value="npm"), mock.patch.object(
            NPM, "capture", side_effect=capture
        ):
            state = NPM.project(self.project, operation="apply")

        self.assertEqual(state, "current")
        self.assertFalse(any(arguments[1] == "install" for arguments in calls))


class NpmGlobalTests(unittest.TestCase):
    def test_status_uses_local_version_without_querying_registry(self):
        with mock.patch.object(NPM.shutil, "which", return_value="npm"), mock.patch.object(
            NPM, "_npm_installed_version", return_value="1.0.0"
        ), mock.patch.object(NPM, "capture") as capture:
            state = NPM.global_package("example-package", operation="status")

        self.assertEqual(state, "current")
        capture.assert_not_called()

    def test_apply_does_not_advance_an_acceptable_install(self):
        with mock.patch.object(NPM.shutil, "which", return_value="npm"), mock.patch.object(
            NPM, "_npm_installed_version", return_value="1.0.0"
        ), mock.patch.object(NPM, "capture") as capture:
            state = NPM.global_package("example-package", operation="apply")

        self.assertEqual(state, "current")
        capture.assert_not_called()

    def test_apply_converges_an_exact_version_drift(self):
        installed_versions = iter(["1.0.0", "2.0.0"])
        with mock.patch.object(NPM.shutil, "which", return_value="npm"), mock.patch.object(
            NPM, "_npm_installed_version", side_effect=installed_versions
        ), mock.patch.object(NPM, "capture", return_value=completed([])) as capture:
            state = NPM.global_package("example-package", operation="apply", requested_version="2.0.0")

        self.assertEqual(state, "current")
        capture.assert_called_once()
        self.assertIn("example-package@2.0.0", capture.call_args.args[0])


class UvToolTests(unittest.TestCase):
    def test_apply_preserves_an_unmanaged_command(self):
        with mock.patch.object(
            UV.shutil, "which", side_effect=lambda name: name
        ), mock.patch.object(
            UV,
            "_uv_tool_installed_version",
            return_value=None,
        ), mock.patch.object(UV, "capture") as capture:
            state = UV.tool("example", "example", operation="apply")

        self.assertEqual(state, "unsupported")
        capture.assert_not_called()

    def test_apply_installs_an_absent_tool(self):
        with mock.patch.object(
            UV.shutil,
            "which",
            side_effect=lambda name: "uv" if name == "uv" else None,
        ), mock.patch.object(
            UV,
            "_uv_tool_installed_version",
            return_value=None,
        ), mock.patch.object(
            UV,
            "_uv_tool_state",
            side_effect=["absent", "current"],
        ), mock.patch.object(
            UV,
            "capture",
            return_value=completed([]),
        ) as capture:
            state = UV.tool("example", "example", operation="apply")

        self.assertEqual(state, "current")
        self.assertIn(
            ["uv", "tool", "install", "example"],
            [call.args[0] for call in capture.call_args_list],
        )

    def test_apply_installs_an_absent_source_tool(self):
        source = "git+ssh://git@example.com/team/example.git"
        with mock.patch.object(
            UV.shutil,
            "which",
            side_effect=lambda name: "uv" if name == "uv" else None,
        ), mock.patch.object(
            UV,
            "_uv_tool_installed_version",
            return_value=None,
        ), mock.patch.object(
            UV,
            "_uv_tool_state",
            side_effect=["absent", "current"],
        ), mock.patch.object(
            UV,
            "capture",
            return_value=completed([]),
        ) as capture:
            state = UV.tool("example", "example", operation="apply", source=source)

        self.assertEqual(state, "current")
        self.assertIn(
            ["uv", "tool", "install", "--from", source, "example"],
            [call.args[0] for call in capture.call_args_list],
        )

    def test_apply_replaces_a_source_tool_installed_from_another_requirement(self):
        source = "git+ssh://git@example.com/team/example.git"
        with mock.patch.object(
            UV.shutil,
            "which",
            side_effect=lambda name: "uv" if name == "uv" else "example",
        ), mock.patch.object(
            UV,
            "_uv_tool_installed_version",
            return_value="1.0.0",
        ), mock.patch.object(
            UV,
            "_uv_tool_state",
            side_effect=["drifted", "current"],
        ), mock.patch.object(
            UV,
            "capture",
            return_value=completed([]),
        ) as capture:
            state = UV.tool("example", "example", operation="apply", source=source)

        self.assertEqual(state, "current")
        self.assertIn(
            [
                "uv",
                "tool",
                "install",
                "--force",
                "--from",
                source,
                "example",
            ],
            [call.args[0] for call in capture.call_args_list],
        )

    def test_installed_requirement_reads_the_uv_source_specifier(self):
        source = "git+ssh://git@example.com/team/example.git"
        listing = subprocess.CompletedProcess(
            [],
            0,
            stdout="example v1.0.0 [required:  {}]\n- example\n".format(source),
            stderr="",
        )
        with mock.patch.object(UV, "capture", return_value=listing) as capture:
            requirement = UV._uv_tool_installed_requirement("uv", "example")

        self.assertEqual(requirement, source)
        capture.assert_called_once_with(
            ["uv", "tool", "list", "--show-version-specifiers"]
        )

    def test_state_rejects_an_editable_requirement_for_a_git_source(self):
        with mock.patch.object(
            UV.shutil, "which", return_value="example"
        ), mock.patch.object(
            UV, "_uv_tool_installed_version", return_value="1.0.0"
        ), mock.patch.object(
            UV,
            "_uv_tool_installed_requirement",
            return_value="file:///workspace/example",
        ), mock.patch.object(
            UV, "capture", return_value=completed([])
        ):
            state = UV._uv_tool_state(
                "uv",
                "example",
                "example",
                source="git+ssh://git@example.com/team/example.git",
            )

        self.assertEqual(state, "drifted")

    def test_state_accepts_the_requested_git_source(self):
        source = "git+ssh://git@example.com/team/example.git"
        with mock.patch.object(
            UV.shutil, "which", return_value="example"
        ), mock.patch.object(
            UV, "_uv_tool_installed_version", return_value="1.0.0"
        ), mock.patch.object(
            UV, "_uv_tool_installed_requirement", return_value=source
        ), mock.patch.object(
            UV, "capture", return_value=completed([])
        ):
            state = UV._uv_tool_state(
                "uv",
                "example",
                "example",
                source=source,
            )

        self.assertEqual(state, "current")

    def test_apply_installs_an_exact_version_from_a_git_source(self):
        source = "git+ssh://git@example.com/team/example.git"
        with mock.patch.object(
            UV.shutil, "which", return_value="uv"
        ), mock.patch.object(
            UV,
            "_uv_tool_installed_version",
            return_value=None,
        ), mock.patch.object(
            UV,
            "_uv_tool_state",
            side_effect=["absent", "current"],
        ), mock.patch.object(
            UV,
            "capture",
            return_value=completed([]),
        ) as capture:
            state = UV.tool(
                "example", "example", operation="apply", requested_version="1.2.3", source=source
            )

        self.assertEqual(state, "current")
        self.assertIn(
            ["uv", "tool", "install", "--from", source, "example"],
            [call.args[0] for call in capture.call_args_list],
        )

    def test_apply_rejects_a_git_source_with_the_wrong_version(self):
        source = "git+ssh://git@example.com/team/example.git"
        with mock.patch.object(UV.shutil, "which", return_value="uv"), mock.patch.object(
            UV, "_uv_tool_installed_version", return_value=None
        ), mock.patch.object(
            UV, "_uv_tool_state", side_effect=["absent", "drifted"]
        ), mock.patch.object(UV, "capture", return_value=completed([])):
            with self.assertRaisesRegex(UV.InstallerError, "remains drifted"):
                UV.tool("example", "example", operation="apply", requested_version="1.2.3", source=source)


class GithubAuthInstallerTests(unittest.TestCase):
    def test_command_environment_ignores_token_sources(self):
        with mock.patch.dict(
            os.environ,
            {
                "GH_TOKEN": "token",
                "GITHUB_TOKEN": "token",
                "GH_ENTERPRISE_TOKEN": "token",
                "GITHUB_ENTERPRISE_TOKEN": "token",
            },
        ):
            environment = GITHUB_AUTH._command_environment(Path("private"))

        for name in GITHUB_AUTH.TOKEN_ENVIRONMENT_VARIABLES:
            self.assertNotIn(name, environment)
        self.assertEqual(environment["GH_CONFIG_DIR"], "private")

    def test_authorization_opens_the_device_page_without_prompting(self):
        process = mock.Mock()
        process.stdout = iter(
            [
                "One-time code copied to clipboard\n",
                "Open this URL to continue: https://github.com/login/device\n",
            ]
        )
        process.wait.return_value = 0
        with mock.patch.object(
            GITHUB_AUTH.subprocess, "Popen", return_value=process
        ) as popen, mock.patch.object(
            GITHUB_AUTH.webbrowser, "open", return_value=True
        ) as open_browser, mock.patch.object(
            GITHUB_AUTH, "ready", return_value=True
        ), mock.patch.object(
            GITHUB_AUTH, "_prepare_auth_directory", return_value=True
        ), mock.patch.object(
            GITHUB_AUTH, "_publish_auth_metadata", return_value=True
        ):
            authorized = GITHUB_AUTH._run_authorization(["gh", "auth", "refresh"])

        self.assertTrue(authorized)
        open_browser.assert_called_once_with(
            "https://github.com/login/device", new=2
        )
        self.assertEqual(popen.call_args.kwargs["stdin"], subprocess.DEVNULL)
        self.assertIn("GH_CONFIG_DIR", popen.call_args.kwargs["env"])
        self.assertNotIn("GH_TOKEN", popen.call_args.kwargs["env"])

    def test_authorization_fails_promptly_when_the_browser_cannot_open(self):
        process = mock.Mock()
        process.stdout = iter(
            ["Open this URL: https://github.com/login/device\n"]
        )
        process.wait.return_value = 1
        with mock.patch.object(
            GITHUB_AUTH.subprocess, "Popen", return_value=process
        ), mock.patch.object(
            GITHUB_AUTH.webbrowser, "open", return_value=False
        ), mock.patch.object(
            GITHUB_AUTH, "ready", return_value=True
        ), mock.patch.object(
            GITHUB_AUTH, "_prepare_auth_directory", return_value=True
        ):
            authorized = GITHUB_AUTH._run_authorization(["gh", "auth", "refresh"])

        self.assertFalse(authorized)
        process.terminate.assert_called_once_with()

    def test_authorization_rejects_plaintext_fallback_metadata(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory)
            (source / "hosts.yml").write_text(
                "github.com:\n    oauth_token: secret\n", encoding="utf-8"
            )
            with mock.patch.object(GITHUB_AUTH, "diagnostic"):
                published = GITHUB_AUTH._publish_auth_metadata(source)

        self.assertFalse(published)

    def test_authorization_prepares_an_existing_temporary_directory(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "source"
            target = root / "target"
            source.mkdir()
            target.mkdir()
            metadata = "github.com:\n    user: example-user\n"
            (source / "hosts.yml").write_text(metadata, encoding="utf-8")

            with mock.patch.object(
                GITHUB_AUTH, "_config_directory", return_value=source
            ):
                prepared = GITHUB_AUTH._prepare_auth_directory(target)

            self.assertTrue(prepared)
            self.assertEqual(
                (target / "hosts.yml").read_text(encoding="utf-8"),
                metadata,
            )

    def test_authorization_publishes_non_secret_host_metadata(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "source"
            destination = root / "destination"
            source.mkdir()
            destination.mkdir()
            metadata = "github.com:\n    user: example-user\n"
            (source / "hosts.yml").write_text(metadata, encoding="utf-8")

            with mock.patch.object(
                GITHUB_AUTH, "_config_directory", return_value=destination
            ):
                published = GITHUB_AUTH._publish_auth_metadata(source)

            self.assertTrue(published)
            self.assertEqual(
                (destination / "hosts.yml").read_text(encoding="utf-8"),
                metadata,
            )

    def test_status_is_read_only_when_key_access_is_available(self):
        status = subprocess.CompletedProcess(
            [],
            0,
            stdout=(
                '{"hosts":{"github.com":[{"active":true,"state":"success",'
                '"tokenSource":"keyring"}]}}'
            ),
            stderr="",
        )
        with mock.patch.object(
            GITHUB_AUTH.shutil, "which", return_value="gh"
        ), mock.patch.object(
            GITHUB_AUTH, "_plaintext_token_present", return_value=False
        ), mock.patch.object(
            GITHUB_AUTH, "_capture", side_effect=[status, completed([])]
        ), mock.patch.object(GITHUB_AUTH, "_run_authorization") as authorize:
            state = GITHUB_AUTH.github_auth("status", "")

        self.assertEqual(state, "current")
        authorize.assert_not_called()

    def test_status_rejects_a_non_keyring_token_source(self):
        status = subprocess.CompletedProcess(
            [],
            0,
            stdout=(
                '{"hosts":{"github.com":[{"active":true,"state":"success",'
                '"tokenSource":"/home/example/.config/gh/hosts.yml"}]}}'
            ),
            stderr="",
        )
        with mock.patch.object(
            GITHUB_AUTH.shutil, "which", return_value="gh"
        ), mock.patch.object(
            GITHUB_AUTH, "_plaintext_token_present", return_value=False
        ), mock.patch.object(
            GITHUB_AUTH, "_capture", return_value=status
        ), mock.patch.object(
            GITHUB_AUTH, "diagnostic"
        ):
            state = GITHUB_AUTH.github_auth("status", "")

        self.assertEqual(state, "drifted")

    def test_apply_refreshes_an_account_missing_key_scope(self):
        with mock.patch.object(
            GITHUB_AUTH,
            "_authentication_state",
            side_effect=[
                ("drifted", True, False),
                ("current", True, False),
            ],
        ), mock.patch.object(
            GITHUB_AUTH, "_run_authorization", return_value=True
        ) as authorize:
            state = GITHUB_AUTH.github_auth("apply", "")

        self.assertEqual(state, "current")
        arguments = authorize.call_args.args[0]
        self.assertEqual(arguments[:3], ["gh", "auth", "refresh"])
        self.assertIn("admin:public_key", arguments)

    def test_apply_logs_in_when_authentication_is_absent(self):
        with mock.patch.object(
            GITHUB_AUTH,
            "_authentication_state",
            side_effect=[("absent", False, False), ("current", True, False)],
        ), mock.patch.object(
            GITHUB_AUTH, "_run_authorization", return_value=True
        ) as authorize:
            state = GITHUB_AUTH.github_auth("apply", "")

        self.assertEqual(state, "current")
        arguments = authorize.call_args.args[0]
        self.assertEqual(arguments[:3], ["gh", "auth", "login"])
        self.assertIn("--clipboard", arguments)
        self.assertIn("admin:public_key", arguments)

    def test_status_reports_failed_authentication_as_absent(self):
        status = subprocess.CompletedProcess([], 1, stdout="", stderr="not logged in")
        with mock.patch.object(
            GITHUB_AUTH.shutil, "which", return_value="gh"
        ), mock.patch.object(
            GITHUB_AUTH, "_plaintext_token_present", return_value=False
        ), mock.patch.object(GITHUB_AUTH, "_capture", return_value=status):
            state = GITHUB_AUTH.github_auth("status", "")

        self.assertEqual(state, "absent")

    def test_apply_blocks_existing_plaintext_credentials_for_manual_migration(self):
        with mock.patch.object(
            GITHUB_AUTH,
            "_authentication_state",
            return_value=("drifted", False, True),
        ), mock.patch.object(
            GITHUB_AUTH, "_run_authorization"
        ) as authorize, mock.patch.object(
            GITHUB_AUTH, "diagnostic"
        ):
            state = GITHUB_AUTH.github_auth("apply", "")

        self.assertEqual(state, "blocked")
        authorize.assert_not_called()


class GithubSshKeyInstallerTests(unittest.TestCase):
    def test_status_is_read_only_when_the_managed_key_is_current(self):
        with mock.patch.object(
            SSH_KEY.shutil, "which", return_value="command"
        ), mock.patch.object(
            SSH_KEY,
            "_key_paths",
            return_value=(Path("private"), Path("public")),
        ), mock.patch.object(
            SSH_KEY,
            "_observe",
            return_value=("current", ("ssh-ed25519", "AAAA"), []),
        ), mock.patch.object(SSH_KEY, "_generate_key") as generate, mock.patch.object(
            SSH_KEY, "_verify_key"
        ) as verify, mock.patch.object(
            GITHUB_SSH_KEY, "_upload_key"
        ) as upload, mock.patch.object(
            SSH_KEY, "_delete_stale_keys"
        ) as delete, mock.patch.dict(
            os.environ, {"DOTFILES_MACHINE_ID": "workstation"}
        ):
            state = GITHUB_SSH_KEY.github_ssh_key("status", "")

        self.assertEqual(state, "current")
        generate.assert_not_called()
        verify.assert_not_called()
        upload.assert_not_called()
        delete.assert_not_called()

    def test_apply_generates_registers_and_verifies_an_absent_key(self):
        identity = ("ssh-ed25519", "AAAA")
        registered = [
            {
                "id": 1,
                "title": "dotfiles:workstation",
                "key": "ssh-ed25519 AAAA",
            }
        ]
        with mock.patch.object(
            SSH_KEY.shutil, "which", return_value="command"
        ), mock.patch.object(
            SSH_KEY,
            "_key_paths",
            return_value=(Path("private"), Path("public")),
        ), mock.patch.object(
            SSH_KEY,
            "_observe",
            side_effect=[("absent", None, []), ("current", identity, registered)],
        ), mock.patch.object(
            SSH_KEY,
            "_local_key",
            return_value=("current", identity),
        ), mock.patch.object(
            GITHUB_SSH_KEY, "_remote_keys", return_value=[]
        ), mock.patch.object(
            SSH_KEY, "_generate_key", return_value=True
        ) as generate, mock.patch.object(
            GITHUB_SSH_KEY, "_upload_key", return_value=True
        ) as upload, mock.patch.object(
            SSH_KEY, "_verify_key", return_value=True
        ) as verify, mock.patch.object(
            SSH_KEY, "_delete_stale_keys"
        ) as delete, mock.patch.dict(
            os.environ, {"DOTFILES_MACHINE_ID": "workstation"}
        ):
            state = GITHUB_SSH_KEY.github_ssh_key("apply", "")

        self.assertEqual(state, "current")
        generate.assert_called_once()
        upload.assert_called_once()
        verify.assert_called_once()
        delete.assert_not_called()

    def test_apply_preserves_a_partial_local_key_pair(self):
        with mock.patch.object(
            SSH_KEY.shutil, "which", return_value="command"
        ), mock.patch.object(
            SSH_KEY,
            "_key_paths",
            return_value=(Path("private"), Path("public")),
        ), mock.patch.object(
            SSH_KEY, "_observe", return_value=("drifted", None, [])
        ), mock.patch.object(
            SSH_KEY, "_generate_key"
        ) as generate, mock.patch.dict(
            os.environ, {"DOTFILES_MACHINE_ID": "workstation"}
        ):
            state = GITHUB_SSH_KEY.github_ssh_key("apply", "")

        self.assertEqual(state, "drifted")
        generate.assert_not_called()

    def test_apply_preserves_stale_same_title_keys(self):
        identity = ("ssh-ed25519", "AAAA")
        inventory = [
            {"id": 1, "title": "dotfiles:workstation", "key": "ssh-ed25519 AAAA"},
            {"id": 2, "title": "dotfiles:workstation", "key": "ssh-ed25519 BBBB"},
        ]
        with mock.patch.object(
            SSH_KEY.shutil, "which", return_value="command"
        ), mock.patch.object(
            SSH_KEY,
            "_key_paths",
            return_value=(Path("private"), Path("public")),
        ), mock.patch.object(
            SSH_KEY,
            "_observe",
            return_value=("current", identity, inventory),
        ), mock.patch.object(
            SSH_KEY, "_verify_key"
        ) as verify, mock.patch.object(
            SSH_KEY, "_delete_stale_keys"
        ) as delete, mock.patch.dict(
            os.environ, {"DOTFILES_MACHINE_ID": "workstation"}
        ):
            state = GITHUB_SSH_KEY.github_ssh_key("apply", "")

        self.assertEqual(state, "current")
        verify.assert_called_once()
        delete.assert_not_called()

    def test_verification_uses_the_accept_new_host_key_policy(self):
        result = subprocess.CompletedProcess(
            [],
            1,
            stdout="",
            stderr="Hi! You've successfully authenticated",
        )
        with mock.patch.object(SSH_KEY, "capture", return_value=result) as capture:
            verified = SSH_KEY._verify_key(
                Path("private"), "github.com", "successfully authenticated"
            )

        self.assertTrue(verified)
        arguments = capture.call_args.args[0]
        self.assertIn("StrictHostKeyChecking=accept-new", arguments)

    def test_exposed_private_key_warns_without_changing_current_state(self):
        result = subprocess.CompletedProcess(
            [], 0, stdout="ssh-ed25519 AAAA\n", stderr=""
        )
        with tempfile.TemporaryDirectory() as temporary_directory:
            private_key = Path(temporary_directory) / "private"
            public_key = Path(temporary_directory) / "private.pub"
            private_key.write_text("private material", encoding="utf-8")
            public_key.write_text("ssh-ed25519 AAAA workstation\n", encoding="utf-8")
            with mock.patch.object(
                SSH_KEY, "capture", return_value=result
            ), mock.patch.object(
                SSH_KEY, "_private_key_exposed", return_value=True
            ), mock.patch.object(SSH_KEY, "diagnostic") as diagnostic:
                state, identity = SSH_KEY._local_key(
                    "GitHub", private_key, public_key
                )

            self.assertEqual(state, "current")
            self.assertEqual(identity, ("ssh-ed25519", "AAAA"))
            self.assertEqual(
                private_key.read_text(encoding="utf-8"), "private material"
            )
            self.assertIn("permissions were not changed", diagnostic.call_args.args[0])

    def test_windows_private_key_acl_probe_returns_a_result(self):
        if os.name != "nt":
            self.skipTest("Windows ACL probe")

        with tempfile.TemporaryDirectory() as temporary_directory:
            private_key = Path(temporary_directory) / "private"
            private_key.write_text("private material", encoding="utf-8")
            exposed = SSH_KEY._private_key_exposed(private_key)

        self.assertIsInstance(exposed, bool)

    def test_apply_rotates_an_unusable_key_before_deleting_it(self):
        old_identity = ("ssh-ed25519", "OLD")
        new_identity = ("ssh-ed25519", "NEW")
        expired = [
            {
                "id": 7,
                "title": "legacy-workstation",
                "key": "ssh-ed25519 OLD",
            }
        ]
        replacement = [
            {
                "id": 8,
                "title": "dotfiles:workstation",
                "key": "ssh-ed25519 NEW",
            }
        ]
        events = []
        upload = mock.Mock(
            side_effect=lambda *_: events.append("upload") or True
        )
        delete = mock.Mock(
            side_effect=lambda *_: events.append("delete") or True
        )
        with mock.patch.object(
            SSH_KEY.shutil, "which", return_value="command"
        ), mock.patch.object(
            SSH_KEY,
            "_key_paths",
            return_value=(Path("private"), Path("public")),
        ), mock.patch.object(
            SSH_KEY,
            "_observe",
            side_effect=[
                ("drifted", old_identity, expired),
                ("current", new_identity, replacement),
            ],
        ), mock.patch.object(
            SSH_KEY,
            "_replacement_key_paths",
            return_value=(Path("replacement"), Path("replacement.pub")),
        ), mock.patch.object(
            SSH_KEY, "_generate_key", return_value=True
        ), mock.patch.object(
            SSH_KEY,
            "_local_key",
            return_value=("current", new_identity),
        ), mock.patch.object(
            SSH_KEY,
            "_verify_key",
            side_effect=lambda *_: events.append("verify") or True,
        ), mock.patch.object(
            SSH_KEY,
            "_activate_replacement",
            side_effect=lambda *_: events.append("activate") or True,
        ), mock.patch.object(
            SSH_KEY, "_remove_key_pair"
        ), mock.patch.dict(
            os.environ, {"DOTFILES_MACHINE_ID": "workstation"}
        ):
            state = SSH_KEY.manage(
                "apply",
                "",
                service_name="GitLab",
                key_filename="gitlab_ed25519",
                required_commands=("glab", "ssh", "ssh-keygen"),
                ssh_target="git@gitlab.example.com",
                authentication_text="welcome to gitlab",
                list_remote_keys=mock.Mock(),
                upload_remote_key=upload,
                delete_remote_key=delete,
                remote_key_usable=lambda _: False,
            )

        self.assertEqual(state, "current")
        self.assertEqual(events, ["upload", "verify", "activate", "delete"])
        delete.assert_called_once_with(7)

    def test_upgrade_does_not_delete_stale_keys_before_verification(self):
        identity = ("ssh-ed25519", "AAAA")
        inventory = [
            {"id": 1, "title": "dotfiles:workstation", "key": "ssh-ed25519 AAAA"},
            {"id": 2, "title": "dotfiles:workstation", "key": "ssh-ed25519 BBBB"},
        ]
        with mock.patch.object(
            SSH_KEY.shutil, "which", return_value="command"
        ), mock.patch.object(
            SSH_KEY,
            "_key_paths",
            return_value=(Path("private"), Path("public")),
        ), mock.patch.object(
            SSH_KEY,
            "_observe",
            return_value=("current", identity, inventory),
        ), mock.patch.object(
            SSH_KEY, "_verify_key", return_value=False
        ), mock.patch.object(
            SSH_KEY, "_delete_stale_keys"
        ) as delete, mock.patch.dict(
            os.environ, {"DOTFILES_MACHINE_ID": "workstation"}
        ):
            state = GITHUB_SSH_KEY.github_ssh_key("upgrade", "")

        self.assertEqual(state, "blocked")
        delete.assert_not_called()

    def test_upgrade_cleanup_deletes_only_stale_managed_title_keys(self):
        identity = ("ssh-ed25519", "AAAA")
        inventory = [
            {"id": 1, "title": "dotfiles:workstation", "key": "ssh-ed25519 AAAA"},
            {"id": 2, "title": "dotfiles:workstation", "key": "ssh-ed25519 BBBB"},
            {"id": 3, "title": "personal", "key": "ssh-ed25519 CCCC"},
        ]
        with mock.patch.object(
            GITHUB_SSH_KEY, "capture", return_value=completed([])
        ) as capture:
            deleted = SSH_KEY._delete_stale_keys(
                inventory,
                identity,
                "dotfiles:workstation",
                GITHUB_SSH_KEY._delete_key,
            )

        self.assertTrue(deleted)
        capture.assert_called_once_with(
            ["gh", "api", "--method", "DELETE", "/user/keys/2"]
        )


class KeyringTests(unittest.TestCase):
    def test_provider_checks_linux_before_probing_for_tools(self):
        provider = load_installer("keyring_provider", "keyring-provider.unix.py")
        with mock.patch.object(provider.sys, "platform", "win32"), mock.patch.object(
            provider, "_linux_tools_present"
        ) as detect_tools, mock.patch.object(provider, "diagnostic") as diagnostic:
            self.assertEqual(provider.provision_keyring("apply", "", "userspace"), "blocked")
        detect_tools.assert_not_called()
        diagnostic.assert_called_once_with("This keyring provider requires Linux.")

    def test_status_is_read_only_and_apply_requires_a_round_trip(self):
        with mock.patch.object(KEYRING_INSTALLER, "ready", return_value=True), mock.patch.object(
            KEYRING_INSTALLER, "check_write", side_effect=[False, True]
        ) as check, mock.patch.object(KEYRING_INSTALLER, "diagnostic"):
            self.assertEqual(KEYRING_INSTALLER.keyring("status", ""), "current")
            check.assert_not_called()
            self.assertEqual(KEYRING_INSTALLER.keyring("apply", ""), "blocked")
            self.assertEqual(KEYRING_INSTALLER.keyring("apply", ""), "current")

    def test_linux_round_trip_removes_the_probe_even_if_readback_fails(self):
        with mock.patch.object(
            KEYRING, "linux_keyring_command", return_value=("secret-tool", {})
        ), mock.patch.object(
            KEYRING, "_run", side_effect=[completed([]), None, completed([])]
        ) as run:
            self.assertFalse(KEYRING._linux_round_trip("probe", "disposable"))
        self.assertEqual([c.args[0][1] for c in run.call_args_list], ["store", "lookup", "clear"])
        self.assertEqual(run.call_args_list[0].kwargs["input"], "disposable")


class RecipeTests(unittest.TestCase):
    def test_keyring_selects_scope_by_privilege_before_the_shared_check(self):
        recipes = ORCHESTRATE.discover_recipes(REPO_ROOT, "unix")
        selected = ORCHESTRATE.resolve_recipes(recipes, ["keyring", "github"])
        for signal, variant in (("available", "systemspace"), ("unavailable", "userspace")):
            with self.subTest(signal=signal), mock.patch.object(
                RECIPE_RESOLVER.subprocess, "run",
                side_effect=lambda args, **kwargs: subprocess.CompletedProcess(
                    args, 0, "linux" if args[-1] == "os" else signal
                ),
            ) as run:
                configs = ORCHESTRATE.install_configs(REPO_ROOT, selected)
                self.assertEqual(configs, [
                    "recipes/04-keyring/unix/{}.conf.yaml".format(variant),
                    "recipes/04-keyring/after.conf.yaml",
                    "recipes/05-github/unix.conf.yaml",
                ])
                self.assertEqual([call.args[0][-1] for call in run.call_args_list], ["os", "noninteractive-sudo"])

    def test_keyring_uses_only_the_shared_check_on_windows_and_macos(self):
        with mock.patch.object(
            RECIPE_RESOLVER.subprocess, "run",
            return_value=subprocess.CompletedProcess([], 0, "macos"),
        ) as run:
            for platform in ("windows", "unix"):
                with self.subTest(platform=platform):
                    recipes = ORCHESTRATE.discover_recipes(REPO_ROOT, platform)
                    selected = ORCHESTRATE.resolve_recipes(recipes, ["keyring"])
                    self.assertEqual(ORCHESTRATE.install_configs(REPO_ROOT, selected), [
                        "recipes/04-keyring/after.conf.yaml",
                    ])
                    self.assertEqual(ORCHESTRATE.test_configs(REPO_ROOT, selected), [
                        "recipes/04-keyring/test.conf.yaml",
                    ])
            self.assertEqual([call.args[0][-1] for call in run.call_args_list], ["os", "os"])

    def test_selector_pairs_install_and_envtest_through_nested_routes(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            recipe = root / "recipes/07-example"
            unix = recipe / "unix"
            branch = unix / "first-choice"
            branch.mkdir(parents=True)
            (root / "install/select").mkdir(parents=True)
            (root / "install/select/host.py").write_text('print("fixture")', encoding="utf-8")
            selector = """- probe:
    platform: [install/select/host.py, os]
- select:
    - when: {platform: fixture}
      target: {}
"""
            (unix / "select.yaml").write_text(selector.replace("{}", "first-choice"), encoding="utf-8")
            (branch / "select.yaml").write_text(selector.replace("{}", "selected"), encoding="utf-8")
            (branch / "selected.conf.yaml").touch()
            (branch / "selected.test.conf.yaml").touch()
            (unix / "before.conf.yaml").touch()
            (unix / "test.conf.yaml").touch()
            (branch / "after.conf.yaml").touch()
            (recipe / "test.conf.yaml").touch()
            self.assertEqual(ORCHESTRATE.discover_recipes(root, "windows"), [])
            with mock.patch.object(
                RECIPE_RESOLVER.subprocess, "run",
                return_value=subprocess.CompletedProcess([], 0, "fixture"),
            ) as run:
                recipes = ORCHESTRATE.discover_recipes(root, "unix")
                self.assertEqual([item.name for item in recipes], ["07-example"])
                run.assert_not_called()
                fragments = RECIPE_RESOLVER.resolve_fragments(root, recipe, "unix")
                run.assert_called_once()
            self.assertEqual(fragments.install, [
                "recipes/07-example/unix/before.conf.yaml",
                "recipes/07-example/unix/first-choice/selected.conf.yaml",
                "recipes/07-example/unix/first-choice/after.conf.yaml",
            ])
            self.assertEqual(fragments.test, [
                "recipes/07-example/test.conf.yaml",
                "recipes/07-example/unix/test.conf.yaml",
                "recipes/07-example/unix/first-choice/selected.test.conf.yaml",
            ])

    def test_agentic_selects_one_codex_profile_and_its_matching_check(self):
        recipe = REPO_ROOT / "recipes/30-agentic"
        for platform, signal, leaf, profile in (
            ("windows", "", "windows", "windows.config.toml"),
            ("unix", "native", "unix/native", "config.toml"),
            ("unix", "wsl", "unix/wsl", "wsl.config.toml"),
        ):
            with self.subTest(leaf=leaf), mock.patch.object(
                RECIPE_RESOLVER.subprocess, "run",
                return_value=subprocess.CompletedProcess([], 0, signal),
            ):
                fragments = RECIPE_RESOLVER.resolve_fragments(REPO_ROOT, recipe, platform)
                target = "config/codex/" + profile
                links = [
                    line.split(": ", 1)[1]
                    for fragment in fragments.install
                    for line in (REPO_ROOT / fragment).read_text(encoding="utf-8").splitlines()
                    if line.strip().startswith("~/.config/codex/config.toml: ")
                ]
                self.assertEqual(links, [target])
                check = f"recipes/30-agentic/{leaf}.test.conf.yaml"
                self.assertIn(check, fragments.test)
                self.assertIn(target, (REPO_ROOT / check).read_text(encoding="utf-8"))

    def test_machine_plan_can_list_optional_recipes_as_comments(self):
        with tempfile.TemporaryDirectory() as directory:
            plan = Path(directory) / ".install-recipes"
            plan.write_text("  # Optional recipes\n\n00-base\n# 50-desktop\n10-dev\n", encoding="utf-8")
            available = ORCHESTRATE.discover_recipes(REPO_ROOT, "unix")
            selected = ORCHESTRATE.read_machine_plan(plan, available)
            self.assertEqual([recipe.name for recipe in selected], ["00-base", "10-dev"])

    def test_selector_rejects_missing_ambiguous_and_unmatched_routes(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            recipe = root / "recipes/07-example"
            unix = recipe / "unix"
            unix.mkdir(parents=True)
            (root / "install/select").mkdir(parents=True)
            (root / "install/select/host.py").write_text('print("fixture")', encoding="utf-8")
            header = "- probe:\n    os: [install/select/host.py, os]\n- select:\n"
            route = "    - when: {os: fixture}\n      target: absent\n"
            cases = (
                (route, "selects missing branch 'absent'"),
                (route * 2, "matched 2 routes"),
                (route.replace("fixture", "other"), "matched 0 routes"),
            )
            for routes, error in cases:
                with self.subTest(error=error):
                    (unix / "select.yaml").write_text(header + routes, encoding="utf-8")
                    with self.assertRaisesRegex(ORCHESTRATE.RecipeError, error):
                        RECIPE_RESOLVER.resolve_fragments(root, recipe, "unix")

    def test_discovers_canonical_platform_recipes(self):
        windows = [recipe.name for recipe in ORCHESTRATE.discover_recipes(REPO_ROOT, "windows")]
        unix = [recipe.name for recipe in ORCHESTRATE.discover_recipes(REPO_ROOT, "unix")]

        self.assertEqual(
            windows,
            [
                "00-base",
                "04-keyring",
                "05-github",
                "10-dev",
                "20-node",
                "30-agentic",
                "40-research",
                "41-iqa",
                "50-desktop",
                "51-collab",
                "52-creative",
                "65-gamedev",
                "90-gaming",
                "95-wsl",
            ],
        )
        self.assertEqual(
            unix,
            [
                "00-base",
                "04-keyring",
                "05-github",
                "10-dev",
                "20-node",
                "30-agentic",
                "40-research",
                "41-iqa",
            ],
        )

    def test_resolves_name_id_tag_and_range_selectors(self):
        recipes = ORCHESTRATE.discover_recipes(REPO_ROOT, "windows")
        expected = ["10-dev", "20-node", "30-agentic"]

        for selectors in (
            ["10-dev", "20-node", "30-agentic"],
            ["10", "20", "30"],
            ["dev", "node", "agentic"],
            ["10...30"],
        ):
            self.assertEqual(
                [recipe.name for recipe in ORCHESTRATE.resolve_recipes(recipes, selectors)],
                expected,
            )

    def test_rejects_duplicate_and_non_monotonic_selections(self):
        recipes = ORCHESTRATE.discover_recipes(REPO_ROOT, "windows")
        with self.assertRaises(ORCHESTRATE.RecipeError):
            ORCHESTRATE.resolve_recipes(recipes, ["dev", "dev"])
        with self.assertRaises(ORCHESTRATE.RecipeError):
            ORCHESTRATE.resolve_recipes(recipes, ["node", "dev"])

    def test_assembles_shared_before_platform_shared_after(self):
        recipes = ORCHESTRATE.discover_recipes(REPO_ROOT, "windows")
        selected = ORCHESTRATE.resolve_recipes(recipes, ["base", "node", "agentic"])

        self.assertEqual(
            ORCHESTRATE.install_configs(REPO_ROOT, selected),
            [
                "recipes/00-base/before.conf.yaml",
                "recipes/00-base/windows.conf.yaml",
                "recipes/00-base/after.conf.yaml",
                "recipes/20-node/before.conf.yaml",
                "recipes/20-node/windows.conf.yaml",
                "recipes/20-node/after.conf.yaml",
                "recipes/30-agentic/before.conf.yaml",
                "recipes/30-agentic/windows.conf.yaml",
                "recipes/30-agentic/after.conf.yaml",
            ],
        )

    def test_example_machine_plan_is_canonical_and_monotonic(self):
        example = REPO_ROOT / ".install-recipes.example"
        entries = []
        for line in example.read_text(encoding="utf-8").splitlines():
            name = line.strip().removeprefix("#").strip()
            if re.fullmatch(r"\d{2}-[a-z0-9-]+", name):
                entries.append(name)
        available = set()
        for platform in ("unix", "windows"):
            with self.subTest(platform=platform):
                recipes = ORCHESTRATE.discover_recipes(REPO_ROOT, platform)
                available.update(recipe.name for recipe in recipes)
                selected = ORCHESTRATE.read_machine_plan(example, recipes)
                self.assertEqual(selected[0].name, "00-base")
        self.assertEqual(entries, sorted(available))

    def test_recipe_parser_preserves_unconsumed_arguments(self):
        cases = (
            (
                ["--recipe", "dev", "node", "--only", "install", "--dry-run", "--upgrade"],
                ["dev", "node"],
                ["--only", "install", "--dry-run", "--upgrade"],
            ),
            (
                ["--recipe", "node", "agentic", "--list-checks"],
                ["node", "agentic"],
                ["--list-checks"],
            ),
        )
        for arguments, expected_selectors, expected_remaining in cases:
            root, selectors, remaining = ORCHESTRATE.parse_recipe_arguments(arguments)
            self.assertIsNone(root)
            self.assertEqual(selectors, expected_selectors)
            self.assertEqual(remaining, expected_remaining)

    def test_assembles_shared_and_platform_test_configs(self):
        recipes = ORCHESTRATE.discover_recipes(REPO_ROOT, "windows")
        selected = ORCHESTRATE.resolve_recipes(recipes, ["base", "node", "agentic"])

        self.assertEqual(
            ORCHESTRATE.test_configs(REPO_ROOT, selected),
            [
                "recipes/00-base/test.conf.yaml",
                "recipes/00-base/windows.test.conf.yaml",
                "recipes/20-node/test.conf.yaml",
                "recipes/20-node/windows.test.conf.yaml",
                "recipes/30-agentic/test.conf.yaml",
                "recipes/30-agentic/windows.test.conf.yaml",
            ],
        )

    def test_every_platform_recipe_has_a_test_config(self):
        for platform in ("unix", "windows"):
            recipes = ORCHESTRATE.discover_recipes(REPO_ROOT, platform)
            configs = ORCHESTRATE.test_configs(REPO_ROOT, recipes)
            for recipe in recipes:
                self.assertTrue(
                    any(config.startswith("recipes/{}/".format(recipe.name)) for config in configs),
                    recipe.name,
                )

    def test_test_launcher_scopes_machine_id_to_envtest(self):
        for identity in ("workstation", None):
            with self.subTest(identity=identity):
                settings = {"ENVTEST_MACHINE_ID": "stale", "ENVTEST_LOG_DIRECTORY": "logs"}
                if identity:
                    settings["DOTFILES_MACHINE_ID"] = identity
                with mock.patch.dict(os.environ, settings, clear=True), mock.patch.object(
                    ORCHESTRATE, "initialize_envtest"
                ), mock.patch.object(ORCHESTRATE.subprocess, "run") as run:
                    ORCHESTRATE.run_test(REPO_ROOT, [], [])
                    child = run.call_args.kwargs["env"]
                    self.assertEqual(child.get("ENVTEST_MACHINE_ID"), identity)
                    self.assertEqual(child["ENVTEST_LOG_DIRECTORY"], "logs")
                    self.assertEqual(os.environ["ENVTEST_MACHINE_ID"], "stale")

    def test_test_adapter_preserves_the_callers_path(self):
        result = subprocess.CompletedProcess([], 0)
        with mock.patch.object(ORCHESTRATE, "initialize_envtest"), mock.patch.object(
            ORCHESTRATE.subprocess, "run", return_value=result
        ) as run:
            returncode = ORCHESTRATE.run_test(
                REPO_ROOT,
                ["recipes/00-base/test.conf.yaml"],
                ["--list-checks"],
            )

        self.assertEqual(returncode, 0)
        invocation = run.call_args.args[0]
        self.assertEqual(
            invocation[2],
            str(REPO_ROOT / "tests" / "envtest_adapter.py"),
        )
        self.assertEqual(
            run.call_args.kwargs["env"]["DOTFILES_ENVTEST_PATH"],
            os.environ.get("PATH", ""),
        )


class ManifestTests(unittest.TestCase):
    def manifests(self):
        return sorted((REPO_ROOT / "recipes").rglob("*.conf.yaml"))

    def references(self):
        references = []
        for manifest in self.manifests():
            for line in manifest.read_text(encoding="utf-8").splitlines():
                stripped = line.strip()
                if stripped.startswith("- install:"):
                    self.assertEqual(stripped, "- install:", (manifest, stripped))
                elif stripped.startswith("- install/"):
                    self.fail("{} must use installer list entries: {}".format(manifest, stripped))
                elif stripped.startswith("- [install/"):
                    match = re.fullmatch(
                        r"- \[(install/[^,\]]+), ([^,\]]+?)\]",
                        stripped,
                    )
                    self.assertIsNotNone(match, (manifest, stripped))
                    references.append((manifest, match.group(1), []))
                elif stripped.startswith("- [[install/"):
                    match = re.fullmatch(
                        r"- \[\[(install/[^,\]]+), (.+)\], ([^,\]]+?)\]",
                        stripped,
                    )
                    self.assertIsNotNone(match, (manifest, stripped))
                    arguments = [
                        value.strip().strip('"')
                        for value in match.group(2).split(",")
                    ]
                    references.append((manifest, match.group(1), arguments))
        return references

    def test_every_directive_resolves_inside_the_repository(self):
        for manifest, reference, _ in self.references():
            path = (REPO_ROOT / reference).resolve()
            try:
                path.relative_to(REPO_ROOT.resolve())
            except ValueError:
                self.fail((manifest, reference))
            self.assertTrue(path.is_file(), (manifest, reference))

    def test_platform_manifests_only_use_compatible_installers(self):
        host_resources = {
            "unix": r"(?:[^/]+(?:\.unix\.py|\.sh)|[^/]+/unix\.(?:py|sh))",
            "windows": r"(?:[^/]+(?:\.windows\.py|\.ps1)|[^/]+/windows\.(?:py|ps1))",
        }
        for manifest, reference, _ in self.references():
            name = manifest.relative_to(REPO_ROOT / "recipes").parts[1].split(".")[0]
            resource = Path(reference).relative_to("install/resources").as_posix()
            shared = re.fullmatch(r"[^/]+(?<!\.unix)(?<!\.windows)\.py", resource)
            platform = re.fullmatch(host_resources.get(name, r"(?!)"), resource)
            self.assertTrue(shared or platform, (manifest, reference))

    def test_every_resource_installer_is_referenced(self):
        resource_installers = {
            path.relative_to(REPO_ROOT).as_posix()
            for path in (REPO_ROOT / "install/resources").rglob("*")
            if path.is_file() and "__pycache__" not in path.parts
        }
        references = {reference for _, reference, _ in self.references()}
        self.assertEqual(resource_installers - references, set())

    def test_node_recipe_owns_one_cross_platform_exact_version(self):
        versions = {
            arguments[-1]
            for manifest, reference, arguments in self.references()
            if reference in {"install/resources/node/unix.sh", "install/resources/node/windows.ps1"}
        }
        self.assertEqual(versions, {"24.19.0"})
        self.assertFalse((REPO_ROOT / "profiles/node-version").exists())

    def test_google_drive_installer_belongs_to_collab_recipe(self):
        collab = (
            REPO_ROOT / "recipes/51-collab/windows.conf.yaml"
        ).read_text(encoding="utf-8")
        research = (
            REPO_ROOT / "recipes/40-research/windows.conf.yaml"
        ).read_text(encoding="utf-8")

        entry = "[[install/resources/winget.ps1, Google.GoogleDrive]"
        self.assertIn(entry, collab)
        self.assertNotIn(entry, research)

    def test_exact_recipe_version_authority_stays_in_manifests(self):
        for manifest, reference, arguments in self.references():
            if not arguments:
                continue
            requested_version = arguments[-1]
            content = (REPO_ROOT / reference).read_text(encoding="utf-8")
            installer_versions = re.findall(
                r"(?<![0-9A-Za-z])v?\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?(?![0-9A-Za-z])",
                content,
            )
            self.assertEqual(
                installer_versions,
                [],
                "{} contains version literals {} but {} owns target {}".format(
                    reference,
                    installer_versions,
                    manifest.relative_to(REPO_ROOT),
                    requested_version,
                ),
            )

class ManifestOrderingTests(unittest.TestCase):
    def test_shellver_resets_inherited_generation_in_plugin_layer(self):
        cases = (
            (
                "config/bash/plugins.bash",
                "unset SHELLVER",
                'eval "$(shellver init bash)"',
            ),
            (
                "config/zsh/plugins.zsh",
                "unset SHELLVER",
                'eval "$(shellver init zsh)"',
            ),
            (
                "config/powershell/plugins.ps1",
                "Remove-Item Env:SHELLVER",
                "init powershell",
            ),
        )

        for path, reset, initialization in cases:
            content = (REPO_ROOT / path).read_text(encoding="utf-8")
            self.assertLess(content.index(reset), content.index(initialization), path)

        for path in (
            "config/bashrc",
            "config/zshrc",
            "config/profile.ps1",
        ):
            content = (REPO_ROOT / path).read_text(encoding="utf-8")
            self.assertNotIn("shellver init", content)

    def test_platform_base_tests_start_with_bootstrap_requirements(self):
        unix = (REPO_ROOT / "recipes/00-base/unix.test.conf.yaml").read_text(
            encoding="utf-8"
        )
        self.assertLess(unix.index("  python:"), unix.index("  fzf:"))

        windows = (REPO_ROOT / "recipes/00-base/windows.test.conf.yaml").read_text(
            encoding="utf-8"
        )
        positions = [
            windows.index("  winget:"),
            windows.index("  python:"),
            windows.index("  terminal:"),
        ]

        self.assertEqual(positions, sorted(positions))

    def test_every_link_manifest_declares_its_cleanup_surface(self):
        recipes_root = REPO_ROOT / "recipes"
        for manifest in recipes_root.rglob("*.conf.yaml"):
            content = manifest.read_text(encoding="utf-8")
            if "\n- link:\n" in "\n" + content:
                shared_before = [
                    parent / "before.conf.yaml"
                    for parent in manifest.parents
                    if parent.is_relative_to(recipes_root) and parent != recipes_root
                ]
                self.assertTrue(
                    any(
                        path.is_file() and "\n- clean:\n" in "\n" + path.read_text(encoding="utf-8")
                        for path in [manifest, *shared_before]
                    ),
                    str(manifest),
                )

    def test_base_defaults_are_shared_and_platform_cleanup_is_local(self):
        before = (REPO_ROOT / "recipes/00-base/before.conf.yaml").read_text(encoding="utf-8")
        self.assertIn("- defaults:", before)
        for platform in ("unix", "windows"):
            manifest = REPO_ROOT / "recipes/00-base" / "{}.conf.yaml".format(platform)
            content = manifest.read_text(encoding="utf-8")
            self.assertNotIn("- defaults:", content, str(manifest))
            self.assertIn("- clean:", content, str(manifest))

    def test_neovim_restore_is_shared_post_platform_work(self):
        action = "install/resources/nvim-plugins.py"
        after = (REPO_ROOT / "recipes/00-base/after.conf.yaml").read_text(encoding="utf-8")
        self.assertIn(action, after)
        for platform in ("unix", "windows"):
            content = (REPO_ROOT / "recipes/00-base" / "{}.conf.yaml".format(platform)).read_text(
                encoding="utf-8"
            )
            self.assertNotIn(action, content)

    def test_cross_platform_recipe_finalizers_are_shared(self):
        for recipe in ("10-dev", "20-node", "30-agentic", "40-research", "41-iqa"):
            after = REPO_ROOT / "recipes" / recipe / "after.conf.yaml"
            self.assertIn("shellver bump machine", after.read_text(encoding="utf-8"))
            for platform in ("unix", "windows"):
                family = after.parent / platform
                manifests = [family.with_suffix(".conf.yaml")]
                manifests.extend(family.rglob("*.conf.yaml"))
                for manifest in manifests:
                    if manifest.is_file() and not manifest.name.endswith(".test.conf.yaml"):
                        self.assertNotIn("shellver bump machine", manifest.read_text(encoding="utf-8"))

    def test_unified_launchers_delegate_to_the_orchestrator(self):
        install_sh = (REPO_ROOT / "install.sh").read_text(encoding="utf-8")
        install_ps1 = (REPO_ROOT / "install.ps1").read_text(encoding="utf-8")
        test_sh = (REPO_ROOT / "test.sh").read_text(encoding="utf-8")
        test_ps1 = (REPO_ROOT / "test.ps1").read_text(encoding="utf-8")

        self.assertIn('${BASEDIR}/orchestrate.py" install unix', install_sh)
        self.assertIn("$ORCHESTRATOR install windows @Args", install_ps1)
        self.assertIn('${BASEDIR}/orchestrate.py" test unix', test_sh)
        self.assertIn("$ORCHESTRATOR test windows @Args", test_ps1)
        self.assertFalse((REPO_ROOT / "install/orchestrate.py").exists())
        self.assertFalse((REPO_ROOT / "install/recipes.py").exists())
        self.assertFalse((REPO_ROOT / "test/orchestrate.py").exists())
        self.assertFalse((REPO_ROOT / "install-profile").exists())
        self.assertFalse((REPO_ROOT / "install-profile.ps1").exists())
        self.assertFalse((REPO_ROOT / "test-profile").exists())
        self.assertFalse((REPO_ROOT / "test-profile.ps1").exists())

    def test_windows_bootstrap_seeds_only_the_base_recipe(self):
        bootstrap = (REPO_ROOT / "bootstrap/init.ps1").read_text(encoding="utf-8")

        self.assertIn(
            '[System.IO.File]::WriteAllText($recipePlanPath, "00-base`n", $utf8WithoutBom)',
            bootstrap,
        )
        self.assertNotIn("Copy-Item .install-recipes.example .install-recipes", bootstrap)

    def test_windows_agentic_owns_persistent_codex_home(self):
        manifest = (REPO_ROOT / "recipes/30-agentic/windows.conf.yaml").read_text(
            encoding="utf-8"
        )
        installer = "install/resources/environment.ps1"
        self.assertIn(installer, manifest)
        self.assertIn('"CODEX_HOME=User:Path:~/.config/codex"', manifest)
        base = (REPO_ROOT / "recipes/00-base/windows.conf.yaml").read_text(
            encoding="utf-8"
        )
        self.assertNotIn(installer, base)

        content = (REPO_ROOT / installer).read_text(encoding="utf-8")
        self.assertIn("Invoke-WindowsEnvironmentVariable -Name $name", content)
        self.assertIn("[EnvironmentVariableTarget]::User", content)
        self.assertIn("[EnvironmentVariableTarget]::Machine", content)
        self.assertNotIn("[Environment]::GetEnvironmentVariable", content)
        self.assertNotIn("[Environment]::SetEnvironmentVariable", content)

        vscode = (REPO_ROOT / "install/resources/vscode-user-data.ps1").read_text(
            encoding="utf-8"
        )
        self.assertIn("Get-WindowsEnvironmentVariableState", vscode)
        self.assertIn("Set-WindowsEnvironmentVariable", vscode)
        self.assertNotIn("[Environment]::GetEnvironmentVariable", vscode)
        self.assertNotIn("[Environment]::SetEnvironmentVariable", vscode)

    def test_bootstraps_ask_before_replacing_an_existing_machine_identity(self):
        windows = (REPO_ROOT / "bootstrap/init.ps1").read_text(encoding="utf-8")
        unix = (REPO_ROOT / "bootstrap/init.sh").read_text(encoding="utf-8")

        for bootstrap in (windows, unix):
            self.assertIn("-y", bootstrap)
            self.assertIn("--yes", bootstrap)
            self.assertIn("--machine_name", bootstrap)
            self.assertIn("DOTFILES_MACHINE_ID", bootstrap)
            self.assertRegex(bootstrap, r"Overwrite the machine name[^\n]*\[y/N\]")
            self.assertIn("00-base", bootstrap)
            self.assertNotIn("dotfiles-local", bootstrap)
        self.assertIn("[System.IO.FileMode]::CreateNew", windows)
        self.assertIn("[System.IO.FileMode]::Truncate", windows)
        self.assertIn("$clonePath = Join-Path $HOME 'dotfiles'", windows)
        self.assertIn("set -C", unix)
        self.assertIn('clone_path="$HOME/dotfiles"', unix)
        self.assertIn("./install.sh", unix)
        self.assertIn("./test.sh", unix)

    def test_shell_machine_loader_exports_the_canonical_identity(self):
        bash = shutil.which("bash")
        if os.name == "nt":
            git = shutil.which("git")
            git_bash = (
                Path(git).parent.parent / "bin/bash.exe" if git else Path()
            )
            bash = str(git_bash) if git_bash.is_file() else None
        if bash is None:
            self.skipTest("bash is not available")

        with tempfile.TemporaryDirectory() as temporary_directory:
            Path(temporary_directory, ".name").write_text(
                "workstation\n", encoding="utf-8"
            )
            shell_link = Path(temporary_directory, ".config", "shell")
            shell_link.parent.mkdir()
            try:
                shell_link.symlink_to(REPO_ROOT / "config/shell", target_is_directory=True)
            except OSError:
                if os.name != "nt":
                    raise
                self.skipTest("creating a directory symlink requires Windows privileges")
            environment = os.environ.copy()
            environment["HOME"] = Path(temporary_directory).as_posix()
            result = subprocess.run(
                [
                    bash,
                    "-c",
                    '. "$1"; printf "%s\n" "$DOTFILES_MACHINE_ID" "$DOTFILES_WORKSPACE_ROOT"',
                    "bash",
                    (REPO_ROOT / "config/shell/machine.sh").as_posix(),
                ],
                env=environment,
                capture_output=True,
                text=True,
                check=False,
            )

        self.assertEqual(result.returncode, 0, result.stderr)
        identity, workspace_root = result.stdout.splitlines()
        self.assertEqual(identity, "workstation")
        self.assertTrue(os.path.samefile(workspace_root, REPO_ROOT))

    def test_powershell_machine_loader_exports_the_canonical_identity(self):
        powershell = shutil.which("pwsh") or shutil.which("powershell")
        if powershell is None:
            self.skipTest("PowerShell is not available")

        with tempfile.TemporaryDirectory() as temporary_directory:
            Path(temporary_directory, ".name").write_text(
                "workstation\n", encoding="utf-8"
            )
            script_path = str(REPO_ROOT / "config/powershell/machine.ps1").replace(
                "'", "''"
            )
            home_path = temporary_directory.replace("'", "''")
            result = subprocess.run(
                [
                    powershell,
                    "-NoProfile",
                    "-NonInteractive",
                    "-Command",
                    ("& '{}' -HomePath '{}'; "
                     "Write-Output $env:DOTFILES_MACHINE_ID $env:DOTFILES_WORKSPACE_ROOT").format(
                        script_path, home_path
                    ),
                ],
                capture_output=True,
                text=True,
                check=False,
            )

        self.assertEqual(result.returncode, 0, result.stderr)
        identity, workspace_root = result.stdout.splitlines()
        self.assertEqual(identity, "workstation")
        self.assertTrue(os.path.samefile(workspace_root, REPO_ROOT))

    def test_prompts_show_machine_identity_and_current_hostname(self):
        powershell = shutil.which("pwsh") or shutil.which("powershell")
        if powershell is not None:
            environment = os.environ.copy()
            environment["DOTFILES_MACHINE_ID"] = "cluster"
            environment["COMPUTERNAME"] = "LOGIN07"
            prompt_path = str(
                REPO_ROOT / "config/powershell/prompt.ps1"
            ).replace("'", "''")
            result = subprocess.run(
                [
                    powershell,
                    "-NoProfile",
                    "-NonInteractive",
                    "-Command",
                    ". '{}'; Write-Output (Get-MachineName)".format(
                        prompt_path
                    ),
                ],
                env=environment,
                capture_output=True,
                text=True,
                check=False,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout.strip(), "cluster : login07")

        bash = shutil.which("bash")
        if os.name == "nt":
            git = shutil.which("git")
            git_bash = (
                Path(git).parent.parent / "bin/bash.exe" if git else Path()
            )
            bash = str(git_bash) if git_bash.is_file() else None
        if bash is not None:
            environment = os.environ.copy()
            environment["DOTFILES_MACHINE_ID"] = "cluster"
            result = subprocess.run(
                [
                    bash,
                    "-c",
                    '. "$1" >/dev/null 2>&1; '
                    'printf "%s\n%s" "$(hostname)" "$(machine_name)"',
                    "bash",
                    (REPO_ROOT / "config/bash/prompt.bash").as_posix(),
                ],
                env=environment,
                capture_output=True,
                text=True,
                check=False,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            lines = result.stdout.splitlines()
            self.assertEqual(len(lines), 2, result.stderr)
            self.assertEqual(lines[1], "cluster : {}".format(lines[0]))


if __name__ == "__main__":
    unittest.main()
