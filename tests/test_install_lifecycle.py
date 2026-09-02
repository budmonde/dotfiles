import contextlib
import io
import os
import re
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
from lifecycle import uv as UV

sys.path.insert(0, str(REPO_ROOT))
import orchestrate as ORCHESTRATE


def completed(arguments):
    return subprocess.CompletedProcess(arguments, 0, stdout="", stderr="")


class FacadeTests(unittest.TestCase):
    def test_public_backend_imports_remain_available(self):
        for name in ("main", "npm_global", "npm_project", "uv_tool"):
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


class RecipeTests(unittest.TestCase):
    def test_discovers_canonical_platform_recipes(self):
        windows = [recipe.name for recipe in ORCHESTRATE.discover_recipes(REPO_ROOT, "windows")]
        unix = [recipe.name for recipe in ORCHESTRATE.discover_recipes(REPO_ROOT, "unix")]

        self.assertEqual(
            windows,
            [
                "00-base",
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
            ["00-base", "10-dev", "20-node", "30-agentic", "40-research", "41-iqa"],
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


if __name__ == "__main__":
    unittest.main()
