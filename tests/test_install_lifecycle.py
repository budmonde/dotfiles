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
sys.path.insert(0, str(REPO_ROOT / "install/lib/python"))
import lifecycle as LIFECYCLE
from lifecycle import core as CORE
from lifecycle import npm as NPM
from lifecycle import ssh_key as SSH_KEY
from lifecycle import uv as UV

sys.path.insert(0, str(REPO_ROOT))
import orchestrate as ORCHESTRATE


def load_installer(module_name, filename):
    spec = importlib.util.spec_from_file_location(
        module_name, REPO_ROOT / "install/shared" / filename
    )
    module = importlib.util.module_from_spec(spec)
    with mock.patch.dict(os.environ, {"DOTBOT_INSTALL_REPO_ROOT": str(REPO_ROOT)}):
        spec.loader.exec_module(module)
    return module


GITHUB_AUTH = load_installer("github_auth_installer", "github-auth.py")
GITHUB_SSH_KEY = load_installer("github_ssh_key_installer", "github-ssh-key.py")


def completed(arguments):
    return subprocess.CompletedProcess(arguments, 0, stdout="", stderr="")


class FacadeTests(unittest.TestCase):
    def test_public_backend_imports_remain_available(self):
        for name in (
            "main",
            "managed_ssh_key",
            "npm_global",
            "npm_project",
            "uv_tool",
        ):
            self.assertTrue(callable(getattr(LIFECYCLE, name)))


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
            state = NPM.npm_project(self.project, "apply")

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
            state = NPM.npm_project(self.project, "apply")

        self.assertEqual(state, "current")
        self.assertFalse(any(arguments[1] == "install" for arguments in calls))


class NpmGlobalTests(unittest.TestCase):
    def test_apply_reports_an_update_without_installing_it(self):
        with mock.patch.object(NPM.shutil, "which", return_value="npm"), mock.patch.object(
            NPM, "_npm_installed_version", return_value="1.0.0"
        ), mock.patch.object(
            NPM, "_npm_state", return_value="update-available"
        ), mock.patch.object(NPM, "capture") as capture:
            state = NPM.npm_global("example-package", "apply")

        self.assertEqual(state, "update-available")
        capture.assert_not_called()

    def test_apply_converges_an_exact_version_drift(self):
        installed_versions = iter(["1.0.0", "2.0.0"])
        with mock.patch.object(NPM.shutil, "which", return_value="npm"), mock.patch.object(
            NPM, "_npm_installed_version", side_effect=installed_versions
        ), mock.patch.object(
            NPM, "_npm_latest_version", return_value="3.0.0"
        ), mock.patch.object(NPM, "capture", return_value=completed([])) as capture:
            state = NPM.npm_global("example-package", "apply", "2.0.0")

        self.assertEqual(state, "update-available")
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
            state = UV.uv_tool("example", "example", "apply")

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
            state = UV.uv_tool("example", "example", "apply")

        self.assertEqual(state, "current")
        self.assertIn(
            ["uv", "tool", "install", "example"],
            [call.args[0] for call in capture.call_args_list],
        )


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

    def test_linux_keyring_initialization_is_temporary(self):
        with mock.patch.object(
            GITHUB_AUTH.sys, "platform", "linux"
        ), mock.patch.object(
            GITHUB_AUTH.shutil, "which", return_value="/usr/bin/secret-tool"
        ), mock.patch.object(
            GITHUB_AUTH.subprocess,
            "run",
            side_effect=[completed([]), completed([])],
        ) as run, mock.patch.object(GITHUB_AUTH, "diagnostic"):
            prepared = GITHUB_AUTH._prepare_linux_keyring()

        self.assertTrue(prepared)
        store = run.call_args_list[0]
        clear = run.call_args_list[1]
        self.assertEqual(store.args[0][1], "store")
        self.assertEqual(store.kwargs["input"], "initialization")
        self.assertEqual(clear.args[0][1], "clear")
        self.assertEqual(clear.kwargs["stdin"], subprocess.DEVNULL)

    def test_linux_keyring_initialization_requires_secret_tool(self):
        with mock.patch.object(
            GITHUB_AUTH.sys, "platform", "linux"
        ), mock.patch.object(
            GITHUB_AUTH.shutil, "which", return_value=None
        ), mock.patch.object(
            GITHUB_AUTH.subprocess, "run"
        ) as run, mock.patch.object(GITHUB_AUTH, "diagnostic"):
            prepared = GITHUB_AUTH._prepare_linux_keyring()

        self.assertFalse(prepared)
        run.assert_not_called()

    def test_non_linux_keyring_initialization_is_a_noop(self):
        with mock.patch.object(
            GITHUB_AUTH.sys, "platform", "darwin"
        ), mock.patch.object(
            GITHUB_AUTH.subprocess, "run"
        ) as run:
            prepared = GITHUB_AUTH._prepare_linux_keyring()

        self.assertTrue(prepared)
        run.assert_not_called()

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
            GITHUB_AUTH, "_prepare_linux_keyring", return_value=True
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
            GITHUB_AUTH, "_prepare_linux_keyring", return_value=True
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
            state = SSH_KEY.managed_ssh_key(
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


class RecipeTests(unittest.TestCase):
    def test_unix_github_recipe_installs_secret_service_before_authentication(self):
        unix = (
            REPO_ROOT / "recipes/unix/05-github.conf.yaml"
        ).read_text(encoding="utf-8")
        windows = (
            REPO_ROOT / "recipes/windows/05-github.conf.yaml"
        ).read_text(encoding="utf-8")

        self.assertLess(unix.index("gnome-keyring"), unix.index("libsecret-tools"))
        self.assertLess(unix.index("libsecret-tools"), unix.index("github-auth.py"))
        self.assertNotIn("gnome-keyring", windows)

    def test_discovers_canonical_platform_recipes(self):
        windows = [recipe.name for recipe in ORCHESTRATE.discover_recipes(REPO_ROOT, "windows")]
        unix = [recipe.name for recipe in ORCHESTRATE.discover_recipes(REPO_ROOT, "unix")]

        self.assertEqual(
            windows,
            [
                "00-base",
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
                "recipes/00-base.before.conf.yaml",
                "recipes/windows/00-base.conf.yaml",
                "recipes/00-base.after.conf.yaml",
                "recipes/20-node.before.conf.yaml",
                "recipes/windows/20-node.conf.yaml",
                "recipes/20-node.after.conf.yaml",
                "recipes/30-agentic.before.conf.yaml",
                "recipes/windows/30-agentic.conf.yaml",
                "recipes/30-agentic.after.conf.yaml",
            ],
        )

    def test_example_machine_plan_is_canonical_and_monotonic(self):
        recipes = ORCHESTRATE.discover_recipes(REPO_ROOT, "windows")
        selected = ORCHESTRATE.read_machine_plan(
            REPO_ROOT / ".install-recipes.example", recipes
        )

        self.assertEqual(selected[0].name, "00-base")
        self.assertEqual(selected[-1].name, "90-gaming")

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
            selectors, remaining = ORCHESTRATE.parse_recipe_arguments(arguments)
            self.assertEqual(selectors, expected_selectors)
            self.assertEqual(remaining, expected_remaining)

    def test_assembles_shared_and_platform_test_configs(self):
        recipes = ORCHESTRATE.discover_recipes(REPO_ROOT, "windows")
        selected = ORCHESTRATE.resolve_recipes(recipes, ["base", "node", "agentic"])

        self.assertEqual(
            ORCHESTRATE.test_configs(REPO_ROOT, selected),
            [
                "recipes/00-base.test.conf.yaml",
                "recipes/windows/00-base.test.conf.yaml",
                "recipes/20-node.test.conf.yaml",
                "recipes/windows/20-node.test.conf.yaml",
                "recipes/30-agentic.test.conf.yaml",
                "recipes/windows/30-agentic.test.conf.yaml",
            ],
        )

    def test_every_platform_recipe_has_a_test_config(self):
        for platform in ("unix", "windows"):
            recipes = ORCHESTRATE.discover_recipes(REPO_ROOT, platform)
            configs = ORCHESTRATE.test_configs(REPO_ROOT, recipes)
            for recipe in recipes:
                self.assertTrue(
                    any("/{}.test.conf.yaml".format(recipe.name) in config for config in configs),
                    recipe.name,
                )

    def test_test_adapter_preserves_the_callers_path(self):
        result = subprocess.CompletedProcess([], 0)
        with mock.patch.object(ORCHESTRATE, "initialize_envtest"), mock.patch.object(
            ORCHESTRATE.subprocess, "run", return_value=result
        ) as run:
            returncode = ORCHESTRATE.run_test(
                REPO_ROOT,
                ["recipes/00-base.test.conf.yaml"],
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
                        r'- \[(install/[^,\]]+), ([^,\]]+?)(?:, "([^"]+)")?\]',
                        stripped,
                    )
                    self.assertIsNotNone(match, (manifest, stripped))
                    references.append((manifest, match.group(1), match.group(3) or ""))
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
        for manifest, reference, _ in self.references():
            relative_manifest = manifest.relative_to(REPO_ROOT).as_posix()
            if relative_manifest.startswith("recipes/unix/"):
                self.assertTrue(reference.startswith(("install/unix/", "install/shared/")))
            if relative_manifest.startswith("recipes/windows/"):
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
            if path.is_file() and "install/lib/" not in path.as_posix()
        }
        references = {reference for _, reference, _ in self.references()}
        self.assertEqual(resource_installers - references, set())

    def test_node_recipe_owns_one_cross_platform_exact_version(self):
        versions = {
            version
            for manifest, reference, version in self.references()
            if reference in {"install/unix/node", "install/windows/node.ps1"}
        }
        self.assertEqual(versions, {"24.19.0"})
        self.assertFalse((REPO_ROOT / "profiles/node-version").exists())

    def test_google_drive_installer_belongs_to_collab_recipe(self):
        collab = (
            REPO_ROOT / "recipes/windows/51-collab.conf.yaml"
        ).read_text(encoding="utf-8")
        research = (
            REPO_ROOT / "recipes/windows/40-research.conf.yaml"
        ).read_text(encoding="utf-8")

        entry = "install/windows/winget/google-drive.ps1"
        self.assertIn(entry, collab)
        self.assertNotIn(entry, research)

    def test_exact_recipe_version_authority_stays_in_manifests(self):
        for manifest, reference, requested_version in self.references():
            if not requested_version:
                continue
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
        unix = (REPO_ROOT / "recipes/unix/00-base.test.conf.yaml").read_text(
            encoding="utf-8"
        )
        self.assertLess(unix.index("  python:"), unix.index("  fzf:"))

        windows = (REPO_ROOT / "recipes/windows/00-base.test.conf.yaml").read_text(
            encoding="utf-8"
        )
        positions = [
            windows.index("  winget:"),
            windows.index("  python:"),
            windows.index("  terminal:"),
        ]

        self.assertEqual(positions, sorted(positions))

    def test_every_link_manifest_declares_its_cleanup_surface(self):
        for manifest in (REPO_ROOT / "recipes").rglob("*.conf.yaml"):
            content = manifest.read_text(encoding="utf-8")
            if "\n- link:\n" in "\n" + content:
                self.assertIn("\n- clean:\n", "\n" + content, str(manifest))

    def test_base_defaults_are_shared_and_platform_cleanup_is_local(self):
        before = (REPO_ROOT / "recipes/00-base.before.conf.yaml").read_text(encoding="utf-8")
        self.assertIn("- defaults:", before)
        for platform in ("unix", "windows"):
            manifest = REPO_ROOT / "recipes" / platform / "00-base.conf.yaml"
            content = manifest.read_text(encoding="utf-8")
            self.assertNotIn("- defaults:", content, str(manifest))
            self.assertIn("- clean:", content, str(manifest))

    def test_neovim_restore_is_shared_post_platform_work(self):
        action = "install/shared/nvim-plugins.py"
        after = (REPO_ROOT / "recipes/00-base.after.conf.yaml").read_text(encoding="utf-8")
        self.assertIn(action, after)
        for platform in ("unix", "windows"):
            content = (REPO_ROOT / "recipes" / platform / "00-base.conf.yaml").read_text(
                encoding="utf-8"
            )
            self.assertNotIn(action, content)

    def test_agentic_shared_setup_is_pre_platform_work(self):
        installer = "install/shared/git-auditor.py"
        before = (REPO_ROOT / "recipes/30-agentic.before.conf.yaml").read_text(
            encoding="utf-8"
        )
        self.assertIn(installer, before)
        for platform in ("unix", "windows"):
            manifest = REPO_ROOT / "recipes" / platform / "30-agentic.conf.yaml"
            self.assertNotIn(installer, manifest.read_text(encoding="utf-8"))

    def test_cross_platform_recipe_finalizers_are_shared(self):
        for recipe in ("10-dev", "20-node", "30-agentic", "40-research", "41-iqa"):
            after = REPO_ROOT / "recipes" / "{}.after.conf.yaml".format(recipe)
            self.assertIn("shellver bump machine", after.read_text(encoding="utf-8"))
            for platform in ("unix", "windows"):
                manifest = REPO_ROOT / "recipes" / platform / "{}.conf.yaml".format(recipe)
                self.assertNotIn("shellver bump machine", manifest.read_text(encoding="utf-8"))

    def test_unified_launchers_delegate_to_the_orchestrator(self):
        install_sh = (REPO_ROOT / "install.sh").read_text(encoding="utf-8")
        install_ps1 = (REPO_ROOT / "install.ps1").read_text(encoding="utf-8")
        test_sh = (REPO_ROOT / "test.sh").read_text(encoding="utf-8")
        test_ps1 = (REPO_ROOT / "test.ps1").read_text(encoding="utf-8")

        self.assertIn('${BASEDIR}/orchestrate.py" install', install_sh)
        self.assertIn("$ORCHESTRATOR install @Args", install_ps1)
        self.assertIn('${BASEDIR}/orchestrate.py" test', test_sh)
        self.assertIn("$ORCHESTRATOR test @Args", test_ps1)
        self.assertFalse((REPO_ROOT / "install/orchestrate.py").exists())
        self.assertFalse((REPO_ROOT / "install/recipes.py").exists())
        self.assertFalse((REPO_ROOT / "test/orchestrate.py").exists())
        self.assertFalse((REPO_ROOT / "install-profile").exists())
        self.assertFalse((REPO_ROOT / "install-profile.ps1").exists())
        self.assertFalse((REPO_ROOT / "test-profile").exists())
        self.assertFalse((REPO_ROOT / "test-profile.ps1").exists())

    def test_windows_bootstrap_seeds_only_the_base_recipe(self):
        bootstrap = (REPO_ROOT / "bootstrap.ps1").read_text(encoding="utf-8")

        self.assertIn(
            '[System.IO.File]::WriteAllText($recipePlanPath, "00-base`n", $utf8WithoutBom)',
            bootstrap,
        )
        self.assertNotIn("Copy-Item .install-recipes.example .install-recipes", bootstrap)

    def test_bootstraps_create_machine_identity_without_overwriting_it(self):
        windows = (REPO_ROOT / "bootstrap.ps1").read_text(encoding="utf-8")
        unix = (REPO_ROOT / "bootstrap.sh").read_text(encoding="utf-8")

        for bootstrap in (windows, unix):
            self.assertIn("--machine_name", bootstrap)
            self.assertIn("DOTFILES_MACHINE_ID", bootstrap)
            self.assertIn("already exists", bootstrap)
            self.assertIn("00-base", bootstrap)
            self.assertNotIn("dotfiles-local", bootstrap)
        self.assertIn("[System.IO.FileMode]::CreateNew", windows)
        self.assertIn("set -C", unix)
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
            environment = os.environ.copy()
            environment["HOME"] = Path(temporary_directory).as_posix()
            result = subprocess.run(
                [
                    bash,
                    "-c",
                    '. "$1"; printf "%s" "$DOTFILES_MACHINE_ID"',
                    "bash",
                    (REPO_ROOT / "config/shell/machine.sh").as_posix(),
                ],
                env=environment,
                capture_output=True,
                text=True,
                check=False,
            )

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "workstation")

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
                    "& '{}' -HomePath '{}'; Write-Output $env:DOTFILES_MACHINE_ID".format(
                        script_path, home_path
                    ),
                ],
                capture_output=True,
                text=True,
                check=False,
            )

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), "workstation")

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
