import argparse
import os
import re
import signal
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, Iterable, List, Optional, Sequence, Tuple


RECIPE_NAME = re.compile(r"^(?P<order>[0-9]{2})-(?P<tag>[a-z0-9][a-z0-9-]*)$")
RECIPE_CONFIG = re.compile(
    r"^(?P<name>[0-9]{2}-[a-z0-9][a-z0-9-]*)\.conf\.yaml$"
)
SHARED_CONFIG = re.compile(
    r"^(?P<name>[0-9]{2}-[a-z0-9][a-z0-9-]*)\.(?:before|after)\.conf\.yaml$"
)
RANGE_SELECTOR = re.compile(r"^(?P<start>[0-9]{2})\.\.\.(?P<end>[0-9]{2})$")
WORKFLOWS = {"install", "test"}


class RecipeError(RuntimeError):
    pass


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
) -> Tuple[Optional[List[str]], List[str]]:
    parser = _RecipeArgumentParser(add_help=False, allow_abbrev=False)
    parser.add_argument("--recipe", action="append", nargs="+")
    options, remaining = parser.parse_known_args(list(arguments))
    selectors = None
    if options.recipe:
        selectors = [value for group in options.recipe for value in group]
    return selectors, [value for value in remaining if value != "--"]


def discover_recipes(repo_root: Path, platform: str) -> List[Recipe]:
    if platform not in {"unix", "windows"}:
        raise RecipeError("Unsupported recipe platform: {}".format(platform))

    recipes_root = repo_root / "recipes"
    identities: Dict[str, Recipe] = {}
    orders: Dict[int, str] = {}
    tags: Dict[str, str] = {}
    platform_names = set()

    for family in ("unix", "windows"):
        family_root = recipes_root / family
        if not family_root.is_dir():
            raise RecipeError("Recipe directory does not exist: {}".format(family_root))
        for path in sorted(family_root.glob("*.conf.yaml")):
            if path.name.endswith(".test.conf.yaml"):
                continue
            match = RECIPE_CONFIG.fullmatch(path.name)
            if match is None:
                raise RecipeError("Invalid recipe filename: {}".format(path))
            name = match.group("name")
            identity = _recipe(name, family)
            existing_order = orders.get(identity.order)
            if existing_order is not None and existing_order != name:
                raise RecipeError(
                    "Recipe order {:02d} is shared by {} and {}".format(
                        identity.order, existing_order, name
                    )
                )
            existing_tag = tags.get(identity.tag)
            if existing_tag is not None and existing_tag != name:
                raise RecipeError(
                    "Recipe tag {} is shared by {} and {}".format(
                        identity.tag, existing_tag, name
                    )
                )
            orders[identity.order] = name
            tags[identity.tag] = name
            identities.setdefault(name, identity)
            if family == platform:
                platform_names.add(name)

    for path in sorted(recipes_root.glob("*.conf.yaml")):
        if path.name.endswith(".test.conf.yaml"):
            continue
        match = SHARED_CONFIG.fullmatch(path.name)
        if match is None:
            raise RecipeError("Invalid shared recipe filename: {}".format(path))
        if match.group("name") not in identities:
            raise RecipeError("Shared fragment has no platform recipe: {}".format(path))

    return [
        Recipe(name=name, order=identities[name].order, tag=identities[name].tag, platform=platform)
        for name in sorted(platform_names, key=lambda value: identities[value].order)
    ]


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
    selectors = [line.strip() for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]
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
    configs = []
    for recipe in recipes:
        before = repo_root / "recipes" / "{}.before.conf.yaml".format(recipe.name)
        platform = repo_root / "recipes" / recipe.platform / "{}.conf.yaml".format(recipe.name)
        after = repo_root / "recipes" / "{}.after.conf.yaml".format(recipe.name)
        if not platform.is_file():
            raise RecipeError("Platform recipe does not exist: {}".format(platform))
        for path in (before, platform, after):
            if path.is_file():
                configs.append(path.relative_to(repo_root).as_posix())
    return configs


def test_configs(repo_root: Path, recipes: Iterable[Recipe]) -> List[str]:
    configs = []
    for recipe in recipes:
        shared = repo_root / "recipes" / "{}.test.conf.yaml".format(recipe.name)
        platform = (
            repo_root
            / "recipes"
            / recipe.platform
            / "{}.test.conf.yaml".format(recipe.name)
        )
        found = False
        for path in (shared, platform):
            if path.is_file():
                configs.append(path.relative_to(repo_root).as_posix())
                found = True
        if not found:
            raise RecipeError("Recipe has no test configuration: {}".format(recipe.name))
    return configs


def initialize_install_submodules(repo_root: Path) -> None:
    targets = ["dotbot", "dotbot-plugins/install"]
    subprocess.run(
        ["git", "submodule", "sync", "--quiet", "--recursive", "--", *targets],
        cwd=str(repo_root),
        check=True,
    )
    subprocess.run(
        ["git", "submodule", "update", "--init", "--recursive", "--", *targets],
        cwd=str(repo_root),
        check=True,
    )


def initialize_envtest(repo_root: Path) -> None:
    subprocess.run(
        ["git", "submodule", "update", "--init", "--recursive", "--", "envtest"],
        cwd=str(repo_root),
        check=True,
    )


def run_install(repo_root: Path, configs: Sequence[str], arguments: Sequence[str]) -> int:
    initialize_install_submodules(repo_root)
    plugin_root = repo_root / "dotbot-plugins" / "install"
    sys.path.insert(0, str(plugin_root))
    from runner import run_dotbot

    invocation = [
        "--plugin",
        str(repo_root / "dotbot-plugins" / "failure_output.py"),
        "--plugin",
        str(plugin_root / "install.py"),
        "-d",
        str(repo_root),
        "-c",
        *configs,
        *arguments,
    ]
    dotbot = repo_root / "dotbot" / "bin" / "dotbot"
    return run_dotbot(dotbot, invocation, cwd=repo_root)


def run_test(repo_root: Path, configs: Sequence[str], arguments: Sequence[str]) -> int:
    initialize_envtest(repo_root)
    invocation = [
        "uv",
        "run",
        str(repo_root / "envtest" / "envtest.py"),
        "--root",
        str(repo_root),
    ]
    for config in configs:
        invocation.extend(("--config", str(repo_root / config)))
    invocation.extend(arguments)
    return subprocess.run(invocation, cwd=str(repo_root), check=False).returncode


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
    root = (repo_root or Path(__file__).resolve().parent).resolve()
    try:
        selectors, remaining = parse_recipe_arguments(values)
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
