import os
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, Iterable, Mapping, Optional, Tuple

import yaml


CONFIGURATION_SCHEMA_VERSION = 1
PLATFORM_NAMES = {"windows", "unix", "linux", "macos", "wsl"}


class ConfigurationError(ValueError):
    pass


@dataclass(frozen=True)
class LinkCheck:
    target: str
    source: str


@dataclass(frozen=True)
class FileCheck:
    path: str
    kind: str


@dataclass(frozen=True)
class PathCheck:
    command: str
    candidate_minimum: int
    selected_any_of: Tuple[str, ...]


@dataclass(frozen=True)
class CommandCheck:
    identifier: str
    argv: Tuple[str, ...]
    exit_code: int
    stdout_contains: Tuple[str, ...]
    stdout_not_contains: Tuple[str, ...]
    stdout_not_matches: Tuple[str, ...]
    stderr_contains: Tuple[str, ...]
    stderr_not_contains: Tuple[str, ...]
    timeout_seconds: int
    live: bool


@dataclass(frozen=True)
class RepositoryCheck:
    identifier: str
    path: str
    clean: bool
    synchronized: bool


@dataclass(frozen=True)
class CheckGroup:
    identifier: str
    enabled: bool
    platforms: Tuple[str, ...]
    environment: Tuple[Tuple[str, str], ...]
    links: Tuple[LinkCheck, ...]
    files: Tuple[FileCheck, ...]
    path: Optional[PathCheck]
    commands: Tuple[CommandCheck, ...]
    repositories: Tuple[RepositoryCheck, ...]

    def applies_to_current_machine(self) -> bool:
        host_platforms = _current_platforms()
        if self.platforms and not host_platforms.intersection(self.platforms):
            return False
        return all(
            bool(os.environ.get(name)) == (expectation == "set")
            for name, expectation in self.environment
        )


@dataclass(frozen=True)
class EnvironmentConfiguration:
    config_paths: Tuple[Path, ...]
    machine_id: Optional[str]
    snapshot_directory: Optional[Path]
    checks: Tuple[CheckGroup, ...]

    def active_checks(self) -> Tuple[CheckGroup, ...]:
        return tuple(
            group
            for group in self.checks
            if group.enabled and group.applies_to_current_machine()
        )

    def select_checks(self, identifiers: Iterable[str]) -> Tuple[CheckGroup, ...]:
        requested = set(identifiers)
        known = {group.identifier for group in self.checks}
        unknown = sorted(requested.difference(known))
        if unknown:
            raise ConfigurationError("unknown check: {}".format(", ".join(unknown)))
        return tuple(group for group in self.checks if group.identifier in requested)


def load_configuration(config_paths: Iterable[Path]) -> EnvironmentConfiguration:
    merged: Dict[str, Any] = {}
    resolved_paths = []

    for config_path in config_paths:
        path = Path(config_path).resolve()
        document = _read_document(path)
        _validate_document(document, path)
        merged = _merge(merged, document)
        resolved_paths.append(path)

    return EnvironmentConfiguration(
        config_paths=tuple(resolved_paths),
        machine_id=_optional_string(merged.get("machine", {}), "id", "machine.id"),
        snapshot_directory=_optional_path(
            merged.get("snapshot", {}), "directory", "snapshot.directory"
        ),
        checks=tuple(
            _parse_check(identifier, check)
            for identifier, check in merged.get("checks", {}).items()
        ),
    )


def _read_document(path: Path) -> Dict[str, Any]:
    try:
        document = yaml.safe_load(path.read_text(encoding="utf-8"))
    except OSError as error:
        raise ConfigurationError("{}: cannot read configuration: {}".format(path, error)) from error
    except yaml.YAMLError as error:
        raise ConfigurationError("{}: invalid YAML: {}".format(path, error)) from error

    if not isinstance(document, dict):
        raise ConfigurationError("{}: configuration root must be a mapping".format(path))
    return document


def _validate_document(document: Mapping[str, Any], path: Path) -> None:
    _validate_known_keys(document, {"schema_version", "machine", "snapshot", "checks"}, path, "")

    schema_version = document.get("schema_version")
    if type(schema_version) is not int or schema_version != CONFIGURATION_SCHEMA_VERSION:
        raise ConfigurationError(
            "{}: schema_version must be {}".format(path, CONFIGURATION_SCHEMA_VERSION)
        )

    _validate_metadata(document.get("machine"), "machine", {"id"}, path)
    _validate_metadata(document.get("snapshot"), "snapshot", {"directory"}, path)
    _validate_checks(document.get("checks"), path)


def _validate_metadata(value: Any, name: str, allowed_keys: set, path: Path) -> None:
    if value is not None and not isinstance(value, dict):
        raise ConfigurationError("{}: {} must be a mapping".format(path, name))
    _validate_known_keys(value or {}, allowed_keys, path, name)
    for key, item in (value or {}).items():
        if not isinstance(item, str) or not item.strip():
            raise ConfigurationError(
                "{}: {}.{} must be a nonempty string".format(path, name, key)
            )


def _validate_checks(value: Any, path: Path) -> None:
    if value is not None and not isinstance(value, dict):
        raise ConfigurationError("{}: checks must be a mapping".format(path))

    for identifier, check in (value or {}).items():
        if not isinstance(identifier, str) or not identifier:
            raise ConfigurationError("{}: checks identifiers must be nonempty strings".format(path))
        if not isinstance(check, dict):
            raise ConfigurationError("{}: checks.{} must be a mapping".format(path, identifier))
        prefix = "checks.{}".format(identifier)
        _validate_known_keys(
            check,
            {
                "enabled",
                "platforms",
                "when",
                "links",
                "files",
                "path",
                "commands",
                "repositories",
            },
            path,
            prefix,
        )
        _validate_optional_boolean(check, "enabled", path, prefix)
        _validate_platforms(check.get("platforms"), path, prefix)
        _validate_when(check.get("when"), path, prefix)
        _validate_links(check.get("links"), path, prefix)
        _validate_files(check.get("files"), path, prefix)
        _validate_path_check(check.get("path"), path, prefix)
        _validate_commands(check.get("commands"), path, prefix)
        _validate_repositories(check.get("repositories"), path, prefix)


def _validate_known_keys(
    value: Mapping[str, Any], allowed_keys: set, path: Path, prefix: str
) -> None:
    for key in value:
        if key not in allowed_keys:
            name = "{}.{}".format(prefix, key) if prefix else str(key)
            raise ConfigurationError("{}: unknown key '{}'".format(path, name))


def _validate_optional_boolean(
    value: Mapping[str, Any], key: str, path: Path, prefix: str
) -> None:
    if key in value and type(value[key]) is not bool:
        raise ConfigurationError("{}: {}.{} must be a boolean".format(path, prefix, key))


def _validate_platforms(value: Any, path: Path, prefix: str) -> None:
    if value is None:
        return
    if not isinstance(value, list) or not value:
        raise ConfigurationError("{}: {}.platforms must be a nonempty list".format(path, prefix))
    for platform in value:
        if not isinstance(platform, str) or platform not in PLATFORM_NAMES:
            raise ConfigurationError(
                "{}: {}.platforms contains an unknown platform".format(path, prefix)
            )


def _validate_when(value: Any, path: Path, prefix: str) -> None:
    if value is None:
        return
    if not isinstance(value, dict):
        raise ConfigurationError("{}: {}.when must be a mapping".format(path, prefix))
    _validate_known_keys(value, {"environment"}, path, "{}.when".format(prefix))
    environment = value.get("environment", {})
    if not isinstance(environment, dict):
        raise ConfigurationError("{}: {}.when.environment must be a mapping".format(path, prefix))
    for name, expectation in environment.items():
        if not isinstance(name, str) or not name:
            raise ConfigurationError(
                "{}: {}.when.environment has an invalid variable name".format(path, prefix)
            )
        if expectation not in {"set", "unset"}:
            raise ConfigurationError(
                "{}: {}.when.environment.{} must be 'set' or 'unset'".format(
                    path, prefix, name
                )
            )


def _validate_links(value: Any, path: Path, prefix: str) -> None:
    if value is None:
        return
    if not isinstance(value, dict):
        raise ConfigurationError("{}: {}.links must be a mapping".format(path, prefix))
    for target, source in value.items():
        if not isinstance(target, str) or not target.strip():
            raise ConfigurationError("{}: {}.links target must be a nonempty string".format(path, prefix))
        if not isinstance(source, str) or not source.strip():
            raise ConfigurationError(
                "{}: {}.links.{} must be a nonempty source path".format(path, prefix, target)
            )


def _validate_files(value: Any, path: Path, prefix: str) -> None:
    if value is None:
        return
    if not isinstance(value, dict):
        raise ConfigurationError("{}: {}.files must be a mapping".format(path, prefix))
    for filename, kind in value.items():
        if not isinstance(filename, str) or not filename.strip():
            raise ConfigurationError("{}: {}.files path must be a nonempty string".format(path, prefix))
        if kind not in {"file", "directory"}:
            raise ConfigurationError(
                "{}: {}.files.{} must be 'file' or 'directory'".format(path, prefix, filename)
            )


def _validate_path_check(value: Any, path: Path, prefix: str) -> None:
    if value is None:
        return
    if not isinstance(value, dict):
        raise ConfigurationError("{}: {}.path must be a mapping".format(path, prefix))
    _validate_known_keys(value, {"command", "candidates", "selected_any_of"}, path, "{}.path".format(prefix))
    if "command" in value and (not isinstance(value["command"], str) or not value["command"].strip()):
        raise ConfigurationError("{}: {}.path.command must be a nonempty string".format(path, prefix))
    candidates = value.get("candidates")
    if candidates is not None:
        if not isinstance(candidates, dict):
            raise ConfigurationError(
                "{}: {}.path.candidates must be a mapping".format(path, prefix)
            )
        _validate_known_keys(candidates, {"minimum"}, path, "{}.path.candidates".format(prefix))
        minimum = candidates.get("minimum")
        if "minimum" in candidates and (type(minimum) is not int or minimum < 1):
            raise ConfigurationError(
                "{}: {}.path.candidates.minimum must be a positive integer".format(path, prefix)
            )
    _validate_string_list(value.get("selected_any_of"), path, "{}.path.selected_any_of".format(prefix))


def _validate_commands(value: Any, path: Path, prefix: str) -> None:
    if value is None:
        return
    if not isinstance(value, dict):
        raise ConfigurationError("{}: {}.commands must be a mapping".format(path, prefix))
    for identifier, command in value.items():
        command_prefix = "{}.commands.{}".format(prefix, identifier)
        if not isinstance(identifier, str) or not identifier:
            raise ConfigurationError("{}: {} has an invalid identifier".format(path, command_prefix))
        if not isinstance(command, dict):
            raise ConfigurationError("{}: {} must be a mapping".format(path, command_prefix))
        _validate_known_keys(
            command,
            {
                "argv",
                "exit_code",
                "stdout_contains",
                "stdout_not_contains",
                "stdout_not_matches",
                "stderr_contains",
                "stderr_not_contains",
                "timeout_seconds",
                "live",
            },
            path,
            command_prefix,
        )
        if "argv" in command:
            _validate_string_list(command["argv"], path, "{}.argv".format(command_prefix), require=True)
        if "exit_code" in command and type(command["exit_code"]) is not int:
            raise ConfigurationError("{}: {}.exit_code must be an integer".format(path, command_prefix))
        for key in (
            "stdout_contains",
            "stdout_not_contains",
            "stdout_not_matches",
            "stderr_contains",
            "stderr_not_contains",
        ):
            _validate_string_list(command.get(key), path, "{}.{}".format(command_prefix, key))
        if "timeout_seconds" in command and (
            type(command["timeout_seconds"]) is not int or command["timeout_seconds"] < 1
        ):
            raise ConfigurationError(
                "{}: {}.timeout_seconds must be a positive integer".format(path, command_prefix)
            )
        _validate_optional_boolean(command, "live", path, command_prefix)


def _validate_repositories(value: Any, path: Path, prefix: str) -> None:
    if value is None:
        return
    if not isinstance(value, dict):
        raise ConfigurationError("{}: {}.repositories must be a mapping".format(path, prefix))
    for identifier, repository in value.items():
        repository_prefix = "{}.repositories.{}".format(prefix, identifier)
        if not isinstance(identifier, str) or not identifier:
            raise ConfigurationError("{}: {} has an invalid identifier".format(path, repository_prefix))
        if not isinstance(repository, dict):
            raise ConfigurationError("{}: {} must be a mapping".format(path, repository_prefix))
        _validate_known_keys(repository, {"path", "clean", "synchronized"}, path, repository_prefix)
        if "path" in repository and (
            not isinstance(repository["path"], str) or not repository["path"].strip()
        ):
            raise ConfigurationError("{}: {}.path must be a nonempty string".format(path, repository_prefix))
        _validate_optional_boolean(repository, "clean", path, repository_prefix)
        _validate_optional_boolean(repository, "synchronized", path, repository_prefix)


def _validate_string_list(
    value: Any, path: Path, name: str, require: bool = False
) -> None:
    if value is None and not require:
        return
    if not isinstance(value, list) or (require and not value):
        raise ConfigurationError("{}: {} must be a nonempty list".format(path, name))
    if any(not isinstance(item, str) or not item for item in value):
        raise ConfigurationError("{}: {} must contain nonempty strings".format(path, name))


def _merge(left: Dict[str, Any], right: Mapping[str, Any]) -> Dict[str, Any]:
    merged = dict(left)
    for key, value in right.items():
        existing = merged.get(key)
        if isinstance(existing, dict) and isinstance(value, dict):
            merged[key] = _merge(existing, value)
        else:
            merged[key] = value
    return merged


def _parse_check(identifier: str, check: Mapping[str, Any]) -> CheckGroup:
    enabled = check.get("enabled", True)
    if not enabled:
        return CheckGroup(
            identifier=identifier,
            enabled=False,
            platforms=(),
            environment=(),
            links=(),
            files=(),
            path=None,
            commands=(),
            repositories=(),
        )

    primitives = {"links", "files", "path", "commands", "repositories"}
    if not primitives.intersection(check):
        raise ConfigurationError("checks.{} must declare at least one primitive".format(identifier))

    return CheckGroup(
        identifier=identifier,
        enabled=True,
        platforms=tuple(check.get("platforms", ())),
        environment=tuple(sorted(check.get("when", {}).get("environment", {}).items())),
        links=tuple(
            LinkCheck(target=target, source=source)
            for target, source in check.get("links", {}).items()
        ),
        files=tuple(
            FileCheck(path=filename, kind=kind)
            for filename, kind in check.get("files", {}).items()
        ),
        path=_parse_path_check(identifier, check.get("path")),
        commands=tuple(
            _parse_command(identifier, command_identifier, command)
            for command_identifier, command in check.get("commands", {}).items()
        ),
        repositories=tuple(
            _parse_repository(identifier, repository_identifier, repository)
            for repository_identifier, repository in check.get("repositories", {}).items()
        ),
    )


def _parse_path_check(identifier: str, value: Optional[Mapping[str, Any]]) -> Optional[PathCheck]:
    if value is None:
        return None
    return PathCheck(
        command=_required_string(value, "command", "checks.{}.path".format(identifier)),
        candidate_minimum=value.get("candidates", {}).get("minimum", 1),
        selected_any_of=tuple(value.get("selected_any_of", ())),
    )


def _parse_command(
    group_identifier: str, identifier: str, command: Mapping[str, Any]
) -> CommandCheck:
    prefix = "checks.{}.commands.{}".format(group_identifier, identifier)
    return CommandCheck(
        identifier=identifier,
        argv=tuple(_required_string_list(command, "argv", prefix)),
        exit_code=command.get("exit_code", 0),
        stdout_contains=tuple(command.get("stdout_contains", ())),
        stdout_not_contains=tuple(command.get("stdout_not_contains", ())),
        stdout_not_matches=tuple(command.get("stdout_not_matches", ())),
        stderr_contains=tuple(command.get("stderr_contains", ())),
        stderr_not_contains=tuple(command.get("stderr_not_contains", ())),
        timeout_seconds=command.get("timeout_seconds", 10),
        live=command.get("live", False),
    )


def _parse_repository(
    group_identifier: str, identifier: str, repository: Mapping[str, Any]
) -> RepositoryCheck:
    prefix = "checks.{}.repositories.{}".format(group_identifier, identifier)
    return RepositoryCheck(
        identifier=identifier,
        path=_required_string(repository, "path", prefix),
        clean=repository.get("clean", False),
        synchronized=repository.get("synchronized", False),
    )


def _required_string(value: Mapping[str, Any], key: str, prefix: str) -> str:
    item = value.get(key)
    if not isinstance(item, str) or not item.strip():
        raise ConfigurationError("{}.{} must be a nonempty string".format(prefix, key))
    return item


def _required_string_list(value: Mapping[str, Any], key: str, prefix: str) -> Tuple[str, ...]:
    item = value.get(key)
    if not isinstance(item, list) or not item or any(not isinstance(part, str) or not part for part in item):
        raise ConfigurationError("{}.{} must be a nonempty list of strings".format(prefix, key))
    return tuple(item)


def _optional_string(section: Mapping[str, Any], key: str, name: str) -> Optional[str]:
    value = section.get(key)
    if value is None:
        return None
    if not isinstance(value, str) or not value.strip():
        raise ConfigurationError("{} must be a nonempty string".format(name))
    return value


def _optional_path(section: Mapping[str, Any], key: str, name: str) -> Optional[Path]:
    value = _optional_string(section, key, name)
    if value is None:
        return None
    return Path(os.path.expandvars(value)).expanduser()


def _current_platforms() -> set:
    platforms = set()
    if os.name == "nt":
        platforms.add("windows")
    else:
        platforms.add("unix")
    if sys.platform.startswith("linux"):
        platforms.add("linux")
        if os.environ.get("WSL_DISTRO_NAME") or _linux_kernel_reports_wsl():
            platforms.add("wsl")
    if sys.platform == "darwin":
        platforms.add("macos")
    return platforms


def _linux_kernel_reports_wsl() -> bool:
    try:
        return "microsoft" in Path("/proc/sys/kernel/osrelease").read_text(
            encoding="utf-8"
        ).lower()
    except OSError:
        return False
