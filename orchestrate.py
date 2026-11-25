import argparse
import os
import re
import signal
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable, List, Optional, Sequence, Tuple

COMMON_ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(COMMON_ROOT / "install/lib"))
from recipe_resolver import RecipeError, has_install_fragments, resolve_fragments


RECIPE_NAME = re.compile(r"^(?P<order>[0-9]{2})-(?P<tag>[a-z0-9][a-z0-9-]*)$")
RANGE_SELECTOR = re.compile(r"^(?P<start>[0-9]{2})\.\.\.(?P<end>[0-9]{2})$")
WORKFLOWS = {"install", "test"}


class _RecipeArgumentParser(argparse.ArgumentParser):
    def error(self, message: str) -> None:
        raise RecipeError(message)


@dataclass(frozen=True)
class Recipe:
    name: str
    order: int
    tag: str
    platform: str


def parse_recipe_arguments(
    arguments: Sequence[str],
) -> Tuple[Optional[Path], Optional[List[str]], List[str]]:
    parser = _RecipeArgumentParser(add_help=False, allow_abbrev=False)
    parser.add_argument("--repo-root", type=Path)
    parser.add_argument("--recipe", action="append", nargs="+")
    options, remaining = parser.parse_known_args(list(arguments))
    selectors = None
    if options.recipe:
        selectors = [value for group in options.recipe for value in group]
    return options.repo_root, selectors, [value for value in remaining if value != "--"]


def discover_recipes(repo_root: Path, platform: str) -> List[Recipe]:
    if platform not in {"unix", "windows"}:
        raise RecipeError("Unsupported recipe platform: {}".format(platform))

    recipes_root = repo_root / "recipes"
    if not recipes_root.is_dir():
        raise RecipeError("Recipe directory does not exist: {}".format(recipes_root))

    recipes = []
    orders = {}
    tags = {}
    for directory in sorted(recipes_root.iterdir()):
        if not directory.is_dir():
            continue
        recipe = _recipe(directory.name, platform)
        if recipe.order in orders:
            raise RecipeError(
                "Recipe order {:02d} is shared by {} and {}".format(
                    recipe.order, orders[recipe.order], recipe.name
                )
            )
        if recipe.tag in tags:
            raise RecipeError(
                "Recipe tag {} is shared by {} and {}".format(
                    recipe.tag, tags[recipe.tag], recipe.name
                )
            )
        orders[recipe.order] = recipe.name
        tags[recipe.tag] = recipe.name
        if has_install_fragments(directory, platform):
            recipes.append(recipe)
    return recipes


def resolve_recipes(recipes: Sequence[Recipe], selectors: Sequence[str]) -> List[Recipe]:
    if not selectors:
        raise RecipeError("At least one recipe selector is required")

    by_name = {recipe.name: recipe for recipe in recipes}
    by_order = {"{:02d}".format(recipe.order): recipe for recipe in recipes}
    by_tag = {recipe.tag: recipe for recipe in recipes}
    resolved: List[Recipe] = []

    for selector in selectors:
        value = selector.strip().lower()
        range_match = RANGE_SELECTOR.fullmatch(value)
        if range_match is not None:
            start = range_match.group("start")
            end = range_match.group("end")
            if start not in by_order or end not in by_order:
                raise RecipeError("Recipe range endpoints must exist: {}".format(selector))
            if int(start) > int(end):
                raise RecipeError("Recipe range is reversed: {}".format(selector))
            resolved.extend(
                recipe
                for recipe in recipes
                if int(start) <= recipe.order <= int(end)
            )
            continue

        recipe = by_name.get(value) or by_order.get(value) or by_tag.get(value)
        if recipe is None:
            raise RecipeError(
                "Unknown recipe {}. Available recipes: {}".format(
                    selector, ", ".join(recipe.name for recipe in recipes)
                )
            )
        resolved.append(recipe)

    seen = set()
    previous = -1
    for recipe in resolved:
        if recipe.name in seen:
            raise RecipeError("Recipe selected more than once: {}".format(recipe.name))
        if recipe.order <= previous:
            raise RecipeError(
                "Recipes must be selected in strictly increasing order: {}".format(
                    " ".join(item.name for item in resolved)
                )
            )
        seen.add(recipe.name)
        previous = recipe.order
    return resolved


def read_machine_plan(path: Path, recipes: Sequence[Recipe]) -> List[Recipe]:
    if not path.is_file():
        raise RecipeError(
            "Machine recipe plan does not exist: {}. Use --recipe or create it from .install-recipes.example".format(
                path
            )
        )
    lines = path.read_text(encoding="utf-8").splitlines()
    selectors = [line for line in map(str.strip, lines) if line and not line.startswith("#")]
    resolved = resolve_recipes(recipes, selectors)
    for selector, recipe in zip(selectors, resolved):
        if selector != recipe.name:
            raise RecipeError(
                "Machine recipe plans require canonical names: {} should be {}".format(
                    selector, recipe.name
                )
            )
    return resolved


def install_configs(repo_root: Path, recipes: Iterable[Recipe]) -> List[str]:
    return _workflow_configs(repo_root, recipes, "install")


def test_configs(repo_root: Path, recipes: Iterable[Recipe]) -> List[str]:
    return _workflow_configs(repo_root, recipes, "test")


def _workflow_configs(repo_root: Path, recipes: Iterable[Recipe], workflow: str) -> List[str]:
    configs = []
    for recipe in recipes:
        directory = repo_root / "recipes" / recipe.name
        fragments = resolve_fragments(repo_root, directory, recipe.platform)
        selected = fragments.install if workflow == "install" else fragments.test
        if not selected:
            raise RecipeError("Recipe has no {} configuration: {}".format(workflow, recipe.name))
        configs.extend(selected)
    return configs


def initialize_install_submodules() -> None:
    targets = ["dotbot", "dotbot-plugins/install"]
    subprocess.run(
        ["git", "submodule", "sync", "--quiet", "--recursive", "--", *targets],
        cwd=str(COMMON_ROOT),
        check=True,
    )
    subprocess.run(
        ["git", "submodule", "update", "--init", "--recursive", "--", *targets],
        cwd=str(COMMON_ROOT),
        check=True,
    )


def initialize_envtest() -> None:
    subprocess.run(
        ["git", "submodule", "update", "--init", "--recursive", "--", "envtest"],
        cwd=str(COMMON_ROOT),
        check=True,
    )


def run_install(repo_root: Path, configs: Sequence[str], arguments: Sequence[str]) -> int:
    initialize_install_submodules()
    plugins = COMMON_ROOT / "dotbot-plugins"
    plugin_root = plugins / "install"
    sys.path.insert(0, str(plugin_root))
    from runner import run_dotbot

    invocation = [
        "--plugin",
        str(plugins / "failure_output.py"),
        "--plugin",
        str(plugin_root / "install.py"),
        "-d",
        str(repo_root),
        "-c",
        *configs,
        *arguments,
    ]
    dotbot = COMMON_ROOT / "dotbot" / "bin" / "dotbot"
    return run_dotbot(dotbot, invocation, cwd=repo_root)


def run_test(repo_root: Path, configs: Sequence[str], arguments: Sequence[str]) -> int:
    initialize_envtest()
    environment = os.environ.copy()
    if environment.get("DOTFILES_MACHINE_ID"):
        environment["ENVTEST_MACHINE_ID"] = environment["DOTFILES_MACHINE_ID"]
    else:
        environment.pop("ENVTEST_MACHINE_ID", None)
    environment["DOTFILES_ENVTEST_PATH"] = environment.get("PATH", "")
    invocation = [
        "uv",
        "run",
        str(COMMON_ROOT / "tests" / "envtest_adapter.py"),
        str(COMMON_ROOT / "envtest" / "envtest.py"),
        "--root",
        str(repo_root),
    ]
    for config in configs:
        invocation.extend(("--config", str(repo_root / config)))
    invocation.extend(arguments)
    return subprocess.run(
        invocation,
        cwd=str(repo_root),
        check=False,
        env=environment,
    ).returncode


def propagate_returncode(returncode: int) -> int:
    if returncode < 0 and os.name != "nt":
        signum = -returncode
        signal.signal(signum, signal.SIG_DFL)
        os.kill(os.getpid(), signum)
    return returncode


def host_family() -> str:
    return "windows" if os.name == "nt" else "unix"


def main(
    arguments: Optional[Sequence[str]] = None,
    repo_root: Optional[Path] = None,
    platform: Optional[str] = None,
) -> int:
    values = list(sys.argv[1:] if arguments is None else arguments)
    if not values or values[0] not in WORKFLOWS:
        print("Expected workflow: install or test", file=sys.stderr)
        return 2

    workflow = values.pop(0)
    if values and values[0] in {"unix", "windows"}:
        platform = values.pop(0)
    try:
        selected_root, selectors, remaining = parse_recipe_arguments(values)
        root = (selected_root or repo_root or COMMON_ROOT).resolve()
        recipes = discover_recipes(root, platform or host_family())
        selection = (
            resolve_recipes(recipes, selectors)
            if selectors is not None
            else read_machine_plan(root / ".install-recipes", recipes)
        )
        if workflow == "install":
            result = run_install(root, install_configs(root, selection), remaining)
        else:
            result = run_test(root, test_configs(root, selection), remaining)
        return propagate_returncode(result)
    except (OSError, RecipeError, subprocess.CalledProcessError) as error:
        print(str(error), file=sys.stderr)
        return 2


def _recipe(name: str, platform: str) -> Recipe:
    match = RECIPE_NAME.fullmatch(name)
    if match is None:
        raise RecipeError("Invalid recipe name: {}".format(name))
    return Recipe(
        name=name,
        order=int(match.group("order")),
        tag=match.group("tag"),
        platform=platform,
    )


if __name__ == "__main__":
    raise SystemExit(main())
