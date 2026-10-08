"""The review log may only grow: records are added, never changed or removed."""

import json
import os
from pathlib import Path
import subprocess
import sys
from tempfile import TemporaryDirectory
import unittest

from tests.baseline_ci import git
from tools.review_log_check import NO_BASE, problems, record_problem

REVIEW = json.dumps({"kind": "review", "id": "r1", "commit": "a" * 40, "date": "2026-10-08",
                     "findings": [], "well_formed": True})
RESOLUTION = json.dumps({"kind": "resolution", "finding": "r1-1", "outcome": "fixed", "date": "2026-10-08"})
LATER = json.dumps({"kind": "review", "id": "r2", "commit": "b" * 40, "date": "2026-10-09",
                    "findings": [], "well_formed": False})
CHECK_TIMEOUT_SECONDS = 10
"""One check reads two small files from a local repository."""


class RecordTest(unittest.TestCase):
    """Each line must be one review or resolution record with its fields."""

    def test_records(self) -> None:
        """Both written kinds pass; text, other JSON values, other kinds and missing fields fail."""
        self.assertIsNone(record_problem(REVIEW))
        self.assertIsNone(record_problem(RESOLUTION))
        broken = {"not json": "not JSON", "[]": "not a JSON object",
                  json.dumps({"kind": "note"}): "unknown record kind 'note'",
                  json.dumps({"kind": 1}): "unknown record kind 1",
                  json.dumps({"kind": "resolution", "finding": "r1-1"}): "missing fields date, outcome"}
        for line, problem in broken.items():
            with self.subTest(line=line):
                self.assertEqual(record_problem(line), problem)


class GrowthTest(unittest.TestCase):
    """Base lines stay unchanged; new lines may be anywhere."""

    def test_accepts_added_and_merged_lines(self) -> None:
        """Appended lines, lines from a merge before or between base lines, and a reorder pass."""
        base = [REVIEW, RESOLUTION]
        for head in ([REVIEW, RESOLUTION, LATER], [LATER, REVIEW, RESOLUTION],
                     [REVIEW, LATER, RESOLUTION], [RESOLUTION, REVIEW]):
            with self.subTest(head=head):
                self.assertEqual(problems(base, head), [])

    def test_refuses_lost_or_changed_lines(self) -> None:
        """A removed line, a changed line and an emptied log each name the lost base line."""
        changed = REVIEW.replace('"well_formed": true', '"well_formed": false')
        self.assertEqual(problems([REVIEW, RESOLUTION], [REVIEW]), ["base line 2 is changed or removed"])
        self.assertEqual(problems([REVIEW], [changed]), ["base line 1 is changed or removed"])
        self.assertEqual(problems([REVIEW], []), ["base line 1 is changed or removed"])

    def test_reports_bad_new_lines(self) -> None:
        """A new line that is not a record fails even when every base line is kept."""
        self.assertEqual(problems([REVIEW], [REVIEW, "{}"]), ["line 2: unknown record kind None"])


class CommandTest(unittest.TestCase):
    """The CI command reads the base log from Git and the head log from the working tree."""

    def run_check(self, root: Path, base: str | None) -> subprocess.CompletedProcess[str]:
        """Run the actual command with an explicit base, as the workflow does."""
        environment = {key: value for key, value in os.environ.items() if key != "REVIEW_LOG_BASE"}
        if base is not None:
            environment["REVIEW_LOG_BASE"] = base
        script = Path(__file__).resolve().parents[1] / "tools/review_log_check.py"
        return subprocess.run([sys.executable, str(script), "--root", str(root)], env=environment,
                              capture_output=True, text=True, timeout=CHECK_TIMEOUT_SECONDS)

    def test_git_base(self) -> None:
        """Growth passes, removal fails, and a base without the log or a new branch has no lines."""
        with TemporaryDirectory() as directory:
            root = Path(directory)
            git(root, "init", "-q")
            (root / "README.md").write_text("fixture\n")

            def commit() -> str:
                """Record a fixture commit without hooks, signatures or a global identity."""
                git(root, "add", ".")
                git(root, "-c", "user.name=Test", "-c", "user.email=test@example.invalid",
                    "-c", "commit.gpgsign=false", "-c", "core.hooksPath=/dev/null", "commit", "-qm", "fixture")
                return git(root, "rev-parse", "HEAD").decode().strip()

            without_log = commit()
            log = root / "reviews/log.jsonl"
            log.parent.mkdir()
            log.write_text(REVIEW + "\n")
            with_log = commit()
            log.write_text(REVIEW + "\n" + LATER + "\n")
            for base in (with_log, without_log, NO_BASE, None):
                with self.subTest(base=base):
                    self.assertEqual(self.run_check(root, base).returncode, 0)
            log.write_text(LATER + "\n")
            failed = self.run_check(root, with_log)
            self.assertEqual(failed.returncode, 1)
            self.assertIn("base line 1 is changed or removed", failed.stderr)
            self.assertNotEqual(self.run_check(root, "main").returncode, 0)


if __name__ == "__main__":
    unittest.main()
