import sys
import tempfile
import unittest
from pathlib import Path


TESTS_DIRECTORY = Path(__file__).resolve().parent
sys.path.insert(0, str(TESTS_DIRECTORY))

from environment.configuration import ConfigurationError, load_configuration


class EnvironmentConfigurationTests(unittest.TestCase):
    def write_config(self, directory: Path, name: str, content: str) -> Path:
        path = directory / name
        path.write_text(content, encoding="utf-8")
        return path

    def test_common_contract_names_every_common_managed_surface(self) -> None:
        configuration = load_configuration([TESTS_DIRECTORY / "environment.yaml"])

        self.assertTrue(
            {
                "common-repository",
                "git",
                "ssh",
                "shell-unix",
                "shell-windows",
                "shellver",
                "fzf",
                "uv",
                "ripgrep",
                "rclone",
                "github-cli",
                "windows-powershell",
                "windows-powershell-modules",
                "windows-fonts",
                "windows-debloat",
            }.issubset({group.identifier for group in configuration.checks})
        )

    def test_later_yaml_layer_can_disable_a_named_group(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            directory = Path(temporary_directory)
            shared = self.write_config(
                directory,
                "shared.yaml",
                """schema_version: 1
checks:
  github-cli:
    path:
      command: gh
""",
            )
            local = self.write_config(
                directory,
                "local.yaml",
                """schema_version: 1
checks:
  github-cli:
    enabled: false
""",
            )

            configuration = load_configuration([shared, local])

        self.assertEqual(len(configuration.checks), 1)
        self.assertFalse(configuration.checks[0].enabled)

    def test_named_check_selection_preserves_the_contract_order(self) -> None:
        configuration = load_configuration([TESTS_DIRECTORY / "environment.yaml"])

        checks = configuration.select_checks(("rclone", "shellver"))

        self.assertEqual(
            tuple(check.identifier for check in checks),
            ("shellver", "rclone"),
        )

    def test_unknown_named_check_is_rejected_before_execution(self) -> None:
        configuration = load_configuration([TESTS_DIRECTORY / "environment.yaml"])

        with self.assertRaisesRegex(ConfigurationError, "unknown check"):
            configuration.select_checks(("not-a-common-check",))

    def test_command_contracts_are_argv_based_with_expected_output(self) -> None:
        configuration = load_configuration([TESTS_DIRECTORY / "environment.yaml"])
        git = next(group for group in configuration.checks if group.identifier == "git")
        version = next(command for command in git.commands if command.identifier == "version")

        self.assertEqual(version.argv, ("git", "--version"))
        self.assertEqual(version.stdout_contains, ("git version",))
        submodules = next(command for command in git.commands if command.identifier == "submodules")
        self.assertEqual(submodules.stdout_not_matches, ("(?m)^-",))

    def test_unknown_check_fields_are_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            config = self.write_config(
                Path(temporary_directory),
                "invalid.yaml",
                """schema_version: 1
checks:
  git:
    version: latest
""",
            )

            with self.assertRaisesRegex(ConfigurationError, "unknown key"):
                load_configuration([config])

    def test_path_contract_requires_a_command_name(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            config = self.write_config(
                Path(temporary_directory),
                "invalid.yaml",
                """schema_version: 1
checks:
  git:
    path:
      candidates:
        minimum: 1
""",
            )

            with self.assertRaisesRegex(ConfigurationError, "path.command"):
                load_configuration([config])
