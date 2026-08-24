# /// script
# requires-python = ">=3.8"
# dependencies = ["PyYAML>=6,<7"]
# ///

import argparse
import sys
import unittest
from pathlib import Path
from typing import Optional, Sequence


TESTS_DIRECTORY = Path(__file__).resolve().parent
sys.path.insert(0, str(TESTS_DIRECTORY))

from environment.configuration import ConfigurationError, load_configuration
from environment.runtime import EnvironmentRuntime, configure_runtime
from environment.suite import environment_suite


def parse_args(arguments: Optional[Sequence[str]] = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Run common environment integration tests."
    )
    parser.add_argument(
        "--config",
        action="append",
        type=Path,
        help="YAML configuration file; later files override earlier files.",
    )
    parser.add_argument(
        "--live",
        action="store_true",
        help="Enable tests that make read-only network requests.",
    )
    parser.add_argument(
        "--check",
        action="append",
        default=[],
        metavar="IDENTIFIER",
        help="Run only this named YAML check group; may be repeated.",
    )
    parser.add_argument(
        "--list-checks",
        action="store_true",
        help="List YAML check groups and whether they apply to this machine.",
    )
    return parser.parse_args(arguments)


def main(arguments: Optional[Sequence[str]] = None) -> int:
    args = parse_args(arguments)
    config_paths = args.config or [TESTS_DIRECTORY / "environment.yaml"]

    try:
        configuration = load_configuration(config_paths)
    except ConfigurationError as error:
        print("configuration error: {}".format(error), file=sys.stderr)
        return 2

    configure_runtime(
        EnvironmentRuntime(configuration=configuration, live=args.live)
    )
    if args.list_checks:
        for check in configuration.checks:
            state = "active" if check.enabled and check.applies_to_current_machine() else "inactive"
            print("{} ({})".format(check.identifier, state))
        return 0

    try:
        integration_suite = environment_suite(configuration, args.live, args.check)
    except ConfigurationError as error:
        print("configuration error: {}".format(error), file=sys.stderr)
        return 2

    suite = unittest.TestSuite()
    if not args.check:
        suite.addTests(
            unittest.defaultTestLoader.discover(
                str(TESTS_DIRECTORY),
                pattern="test_environment_*.py",
                top_level_dir=str(TESTS_DIRECTORY),
            )
        )
    suite.addTests(integration_suite)
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    return 0 if result.wasSuccessful() else 1


if __name__ == "__main__":
    raise SystemExit(main())
