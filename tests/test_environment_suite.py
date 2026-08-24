import sys
import unittest
from pathlib import Path
from unittest.mock import patch


TESTS_DIRECTORY = Path(__file__).resolve().parent
sys.path.insert(0, str(TESTS_DIRECTORY))

from environment.configuration import CheckGroup, CommandCheck
from environment.contracts import CommandResult


class EnvironmentSuiteTests(unittest.TestCase):
    def test_failed_command_assertion_does_not_include_captured_output(self) -> None:
        from environment.suite import EnvironmentCheckTest

        group = CheckGroup(
            identifier="sanitized-command-output",
            enabled=True,
            platforms=(),
            environment=(),
            links=(),
            files=(),
            path=None,
            commands=(
                CommandCheck(
                    identifier="safe-diagnostic",
                    argv=("example",),
                    exit_code=0,
                    stdout_contains=("expected",),
                    stdout_not_contains=(),
                    stdout_not_matches=(),
                    stderr_contains=(),
                    stderr_not_contains=(),
                    timeout_seconds=1,
                    live=False,
                ),
            ),
            repositories=(),
        )
        test = EnvironmentCheckTest(group, live=False)
        result = unittest.TestResult()

        with patch(
            "environment.suite.command_result",
            return_value=CommandResult(0, "secret-output", ""),
        ):
            test.run(result)

        self.assertEqual(len(result.failures), 1)
        self.assertNotIn("secret-output", result.failures[0][1])
