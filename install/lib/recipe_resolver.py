import re
import subprocess
import sys
from pathlib import Path
from typing import Dict, List, NamedTuple, Optional, Tuple


class RecipeError(RuntimeError):
    pass


class RecipeFragments(NamedTuple):
    install: List[str]
    test: List[str]


SHARED_INSTALL = ("before.conf.yaml", "after.conf.yaml")
BRANCH_NAME = re.compile(r"[a-zA-Z0-9][a-zA-Z0-9_-]*")
PROBE_TIMEOUT = 10


def has_install_fragments(directory: Path, platform: str) -> bool:
    return (
        any((directory / filename).is_file() for filename in SHARED_INSTALL)
        or (directory / (platform + ".conf.yaml")).is_file()
        or (directory / platform).is_dir()
    )


def resolve_fragments(repo_root: Path, directory: Path, platform: str) -> RecipeFragments:
    install, test = _platform_fragments(repo_root, directory, platform, {})
    before, after = (directory / name for name in SHARED_INSTALL)
    return RecipeFragments(
        [
            path.relative_to(repo_root).as_posix()
            for path in (before, install, after)
            if path is not None and path.is_file()
        ],
        [
            path.relative_to(repo_root).as_posix()
            for path in (directory / "test.conf.yaml", test)
            if path is not None and path.is_file()
        ],
    )


def _platform_fragments(
    repo_root: Path,
    directory: Path,
    name: str,
    signals: Dict[Tuple[str, ...], str],
    required: bool = False,
) -> Tuple[Optional[Path], Optional[Path]]:
    install = directory / (name + ".conf.yaml")
    test = directory / (name + ".test.conf.yaml")
    branch = directory / name
    if branch.is_dir():
        if install.exists() or test.exists():
            raise RecipeError(
                "{} declares both a selector directory and a recipe leaf".format(branch)
            )
        selector = branch / "select.yaml"
        target = _select_branch(repo_root, selector, signals)
        if target is None:
            return None, None
        return _platform_fragments(repo_root, branch, target, signals, required=True)
    if required and not (install.is_file() or test.is_file()):
        raise RecipeError("{} selects missing branch '{}'".format(directory / "select.yaml", name))
    return install, test


def _selector_data(selector: Path):
    # Planning can run before either workflow initializes its submodules.
    common_root = Path(__file__).resolve().parents[2]
    yaml_library = common_root / "dotbot/lib/pyyaml/lib"
    try:
        contents = selector.read_text(encoding="utf-8")
        if not (yaml_library / "yaml/__init__.py").is_file():
            subprocess.run(
                ["git", "submodule", "update", "--init", "--recursive", "--", "dotbot"],
                cwd=str(common_root),
                check=True,
            )
        if not (yaml_library / "yaml/__init__.py").is_file():
            raise RecipeError("{}: Dotbot's vendored PyYAML is missing".format(selector))
        if str(yaml_library) not in sys.path:
            sys.path.insert(0, str(yaml_library))
        import yaml
    except (OSError, UnicodeError, ImportError, subprocess.CalledProcessError) as error:
        raise RecipeError("{}: {}".format(selector, error)) from error

    try:
        return yaml.safe_load(contents)
    except yaml.YAMLError as error:
        raise RecipeError("{}: {}".format(selector, error)) from error


def _select_branch(
    repo_root: Path, selector: Path, signals: Dict[Tuple[str, ...], str]
) -> Optional[str]:
    directives = _selector_data(selector)
    if (
        not isinstance(directives, list)
        or len(directives) != 2
        or any(not isinstance(item, dict) or len(item) != 1 for item in directives)
        or set().union(*directives) != {"probe", "select"}
    ):
        raise RecipeError("{} must declare one probe and one select directive".format(selector))
    definitions = {name: value for item in directives for name, value in item.items()}
    probes, routes = definitions["probe"], definitions["select"]
    if not isinstance(probes, dict) or not probes or not isinstance(routes, list) or not routes:
        raise RecipeError("{} requires named probes and a list of routes".format(selector))
    for name, command in probes.items():
        if (
            not isinstance(name, str)
            or not name
            or not isinstance(command, list)
            or not command
            or any(not isinstance(value, str) or not value for value in command)
        ):
            raise RecipeError("{} defines an invalid probe: {}".format(selector, name))
    for route in routes:
        if not isinstance(route, dict) or set(route) != {"when", "target"}:
            raise RecipeError("{} routes require when and target".format(selector))
        conditions, target = route["when"], route["target"]
        if (
            not isinstance(conditions, dict)
            or not conditions
            or any(
                key not in probes or not isinstance(value, str) or not value
                for key, value in conditions.items()
            )
        ):
            raise RecipeError("{} defines invalid route conditions".format(selector))
        if target is not None and (not isinstance(target, str) or not BRANCH_NAME.fullmatch(target)):
            raise RecipeError("{} defines an invalid branch target: {}".format(selector, target))

    selected = [
        route["target"]
        for route in routes
        if all(
            _probe(repo_root, selector, probes[name], signals) == value
            for name, value in route["when"].items()
        )
    ]
    if len(selected) != 1:
        raise RecipeError("{} matched {} routes, expected one".format(selector, len(selected)))
    return selected[0]


def _probe(
    repo_root: Path,
    selector: Path,
    command: List[str],
    signals: Dict[Tuple[str, ...], str],
) -> str:
    key = tuple(command)
    if key not in signals:
        configured = Path(command[0])
        script = (repo_root / configured).resolve()
        try:
            script.relative_to(repo_root.resolve() / "install/select")
        except ValueError as error:
            raise RecipeError(
                "{} probe must be under install/select: {}".format(selector, configured)
            ) from error
        if (
            configured.is_absolute()
            or configured.drive
            or script.suffix != ".py"
            or not script.is_file()
        ):
            raise RecipeError("{} defines an invalid Python probe: {}".format(selector, configured))
        try:
            result = subprocess.run(
                [sys.executable, str(script), *command[1:]],
                cwd=str(repo_root),
                stdin=subprocess.DEVNULL,
                capture_output=True,
                text=True,
                encoding="utf-8",
                errors="replace",
                timeout=PROBE_TIMEOUT,
                check=False,
            )
        except (OSError, subprocess.TimeoutExpired) as error:
            raise RecipeError("{} could not run {}: {}".format(selector, configured, error)) from error
        output = result.stdout.strip().splitlines()
        if result.returncode or len(output) != 1:
            diagnostic = result.stderr.strip() or "expected one signal on stdout"
            raise RecipeError("{} probe {} failed: {}".format(selector, configured, diagnostic))
        signals[key] = output[0]
    return signals[key]
