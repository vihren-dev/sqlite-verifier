"""Prevent CI routing from skipping verifier/runtime changes or weakening release checks."""

from pathlib import Path
from tempfile import TemporaryDirectory
import json
import os
import subprocess
import sys
import unittest

from tests.baseline_ci import git
from tests.ci_scope import scope


class CiScopeTest(unittest.TestCase):
    """Keep documentation, verification and packaging scopes explicit and conservative."""

    def test_change_scopes(self) -> None:
        """Unknown paths run the Nix targets; host checks run only for their own subjects."""
        examples = [(["README.md", "docs/ci.md"], "docs"), (["plans/20261007-task.md"], "docs"),
                    (["docs/nested/guide.md"], "docs"), (["unknown/file.md"], "test"),
                    (["reviews/log.jsonl"], "docs"), (["docs/adr.md", "reviews/log.jsonl"], "docs"),
                    (["reviews/log.jsonl", "tools/review.py"], "test"),
                    (["reviews/log.jsonl", "parser/main.c"], "package"),
                    (["reviews/other.jsonl"], "test"), (["reviews/notes.md"], "test"),
                    (["log.jsonl"], "test"),
                    (["parser/upstream/README.md"], "package"),
                    (["SqliteVerifier/Preservation.lean"], "test"),
                    (["tests/coverage_test.py"], "test"), (["unknown/file"], "test"),
                    (["migration_check/prepare.py"], "test"), (["tools/review.py"], "test"),
                    (["packaging/install.py"], "packaging"), (["nix/flake.lock"], "package"),
                    (["tools/check_resources.py"], "infrastructure"),
                    (["build-support/default.nix"], "package"),
                    (["build-support/tests.nix"], "infrastructure"),
                    (["tests/test_toolchain_smoke.py"], "packaging"),
                    (["tests/test_source_identity.py"], "infrastructure"),
                    (["tests/test_nix_test_targets.py"], "infrastructure"),
                    (["tests/environment_snapshot_test.py"], "infrastructure"),
                    (["tests/test_runtime_package.py"], "infrastructure"),
                    (["tests/nix_suites.json"], "infrastructure"),
                    (["pytest.ini"], "infrastructure"), (["tests/conftest.py"], "infrastructure"),
                    (["conftest.py"], "infrastructure"),
                    (["tests/runtime_support.py"], "infrastructure"),
                    (["tests/new_shared_helper.py"], "infrastructure"),
                    (["tests/runtime_installation.py"], "package"),
                    (["tests/test_translation.py"], "test"),
                    (["docs/install.md"], "packaging"),
                    (["README.md", "parser/main.c"], "package"),
                    (["migration_check/runtime.py"], "packaging"),
                    (["examples/atuin/Proofs.lean"], "test"),
                    (["migration_check/runtime.py", "tests/nix_suites.json"], "package"),
                    ([".github/workflows/ci.yml"], "package"), ([], "package")]
        for paths, expected in examples:
            with self.subTest(paths=paths):
                self.assertEqual(scope(paths, "pull_request", "refs/pull/2/merge"), expected)

    def test_full_runs(self) -> None:
        """Releases, manual, scheduled and main runs check everything; main skips only docs."""
        self.assertEqual(scope(["README.md"], "push", "refs/tags/v1-rc.1"), "package")
        self.assertEqual(scope(["README.md"], "workflow_dispatch", "refs/heads/main"), "package")
        self.assertEqual(scope([], "schedule", "refs/heads/main"), "package")
        self.assertEqual(scope(["tests/test_translation.py"], "push", "refs/heads/main"), "package")
        self.assertEqual(scope(["docs/ci.md"], "push", "refs/heads/main"), "docs")

    def test_real_diff_preserves_removed_runtime_paths(self) -> None:
        """Renaming runtime source to Markdown still packages, using the actual CI entrypoint."""
        with TemporaryDirectory() as directory:
            root = Path(directory)
            git(root, "init", "-q")
            (root / "parser").mkdir()
            source = root / "parser/main.c"
            source.write_text("fixture")

            def commit() -> str:
                """Record a local fixture without hooks, signatures or global identity requirements."""
                git(root, "add", ".")
                git(root, "-c", "user.name=Test", "-c", "user.email=test@example.invalid",
                    "-c", "commit.gpgsign=false", "-c", "core.hooksPath=/dev/null", "commit", "-qm", "fixture")
                return git(root, "rev-parse", "HEAD").decode().strip()

            base = commit()
            (root / "docs").mkdir()
            source.rename(root / "docs/main.md")
            commit()
            event, output = root / "event.json", root / "output"
            event.write_text(json.dumps({"pull_request": {"base": {"sha": base}}}))
            environment = {**os.environ, "GITHUB_EVENT_NAME": "pull_request", "GITHUB_REF": "refs/pull/2/merge",
                           "GITHUB_EVENT_PATH": str(event), "GITHUB_OUTPUT": str(output)}
            subprocess.run([sys.executable, str(Path(__file__).with_name("ci_scope.py"))], cwd=root,
                           env=environment, check=True, capture_output=True, timeout=10)
            self.assertEqual(output.read_text(), "scope=package\n")


if __name__ == "__main__":
    unittest.main()
