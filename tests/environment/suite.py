import re
import unittest
from typing import Iterable

from environment.configuration import CheckGroup, EnvironmentConfiguration
from environment.contracts import (
    command_result,
    path_candidates,
    repository_state,
    required_file_path,
    resolved_link_target,
    selected_paths,
    source_path,
)


class EnvironmentCheckTest(unittest.TestCase):
    def __init__(self, group: CheckGroup, live: bool) -> None:
        super().__init__("runTest")
        self.group = group
        self.live = live

    def id(self) -> str:
        return "environment.{}".format(self.group.identifier)

    def __str__(self) -> str:
        return "environment check: {}".format(self.group.identifier)

    def shortDescription(self) -> str:
        primitives = []
        if self.group.links:
            primitives.append("links")
        if self.group.files:
            primitives.append("files")
        if self.group.path is not None:
            primitives.append("PATH")
        if self.group.commands:
            primitives.append("commands")
        if self.group.repositories:
            primitives.append("repositories")
        return ", ".join(primitives)

    def runTest(self) -> None:
        if not self.group.enabled:
            self.skipTest("disabled by configuration")
        if not self.group.applies_to_current_machine():
            self.skipTest("not applicable to this machine")

        self._assert_links()
        self._assert_files()
        self._assert_path()
        self._assert_commands()
        self._assert_repositories()

    def _assert_links(self) -> None:
        for contract in self.group.links:
            with self.subTest(primitive="link", target=contract.target):
                self.assertEqual(resolved_link_target(contract), source_path(contract))

    def _assert_files(self) -> None:
        for contract in self.group.files:
            with self.subTest(primitive="file", path=contract.path):
                path = required_file_path(contract)
                self.assertTrue(path.exists())
                if contract.kind == "file":
                    self.assertTrue(path.is_file())
                if contract.kind == "directory":
                    self.assertTrue(path.is_dir())

    def _assert_path(self) -> None:
        contract = self.group.path
        if contract is None:
            return
        with self.subTest(primitive="PATH", command=contract.command):
            candidates = path_candidates(contract.command)
            self.assertGreaterEqual(len(candidates), contract.candidate_minimum)
            self.assertTrue(candidates)
            if contract.selected_any_of:
                self.assertIn(candidates[0], selected_paths(contract.selected_any_of))

    def _assert_commands(self) -> None:
        for contract in self.group.commands:
            with self.subTest(primitive="command", command=contract.identifier):
                if contract.live and not self.live:
                    continue
                result = command_result(contract)
                self.assertEqual(result.returncode, contract.exit_code)
                for expected in contract.stdout_contains:
                    self.assertTrue(
                        expected in result.stdout,
                        "expected stdout fragment was absent",
                    )
                for unexpected in contract.stdout_not_contains:
                    self.assertFalse(
                        unexpected in result.stdout,
                        "unexpected stdout fragment was present",
                    )
                for pattern in contract.stdout_not_matches:
                    self.assertIsNone(
                        re.search(pattern, result.stdout),
                        "stdout matched a prohibited pattern",
                    )
                for expected in contract.stderr_contains:
                    self.assertTrue(
                        expected in result.stderr,
                        "expected stderr fragment was absent",
                    )
                for unexpected in contract.stderr_not_contains:
                    self.assertFalse(
                        unexpected in result.stderr,
                        "unexpected stderr fragment was present",
                    )

    def _assert_repositories(self) -> None:
        for contract in self.group.repositories:
            with self.subTest(primitive="repository", repository=contract.identifier):
                state = repository_state(contract)
                if contract.clean:
                    self.assertEqual(state.worktree_status, "")
                if contract.synchronized:
                    self.assertEqual(state.ahead, 0)
                    self.assertEqual(state.behind, 0)


def environment_suite(
    configuration: EnvironmentConfiguration,
    live: bool,
    selected_identifiers: Iterable[str],
) -> unittest.TestSuite:
    selected_identifiers = tuple(selected_identifiers)
    if selected_identifiers:
        groups = configuration.select_checks(selected_identifiers)
    else:
        groups = configuration.active_checks()
    return unittest.TestSuite(EnvironmentCheckTest(group, live) for group in groups)
