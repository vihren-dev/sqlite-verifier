"""Check actual child overlap, complete diagnostics, deadlines and joined failures."""

from pathlib import Path
import subprocess
import sys
from tempfile import TemporaryDirectory
import unittest

ROOT = Path(__file__).resolve().parents[1]


class IndependentSuiteTests(unittest.TestCase):
    """Use child rendezvous instead of machine-speed assertions to prove overlap."""

    def test_overlap_failure_join_and_timeout(self) -> None:
        """A failing or timed-out sibling cannot hide the other's completed output."""
        with TemporaryDirectory() as temporary:
            root = Path(temporary)
            first, second = root / "first.py", root / "second.py"
            for exit_code in (0, 7):
                with self.subTest(exit_code=exit_code):
                    first.write_text(
                        "from pathlib import Path\nimport time, sys\n"
                        "Path('first-ready').touch()\n"
                        "while not Path('second-ready').exists(): time.sleep(0.01)\n"
                        "print('first stdout')\nprint('first stderr', file=sys.stderr)\n"
                        "Path('first-finished').touch()\n"
                        f"raise SystemExit({exit_code})\n")
                    second.write_text(
                        "from pathlib import Path\nimport time, sys\n"
                        "Path('second-ready').touch()\n"
                        "while not Path('first-finished').exists(): time.sleep(0.01)\n"
                        "time.sleep(0.1)\nPath('second-finished').touch()\n"
                        "print('second stdout')\nprint('second stderr', file=sys.stderr)\n")
                    result = self.invoke(root, ((str(first), 3), (str(second), 3)))
                    self.assertEqual(result.returncode, int(exit_code != 0), result.stdout + result.stderr)
                    self.assertTrue((root / "second-finished").exists())
                    for name in ("first", "second"):
                        log = (root / "build/test-logs" / f"{name}.log").read_text()
                        self.assertIn(f"{name} stdout", log)
                        self.assertIn(f"{name} stderr", log)
                        self.assertIn(log, result.stdout)
                    self.assertIn(f"exit {exit_code}", result.stdout)
                    self.assertIn("s total", result.stdout)
                    for marker in root.glob("*-ready"):
                        marker.unlink()
                    for marker in root.glob("*-finished"):
                        marker.unlink()
            first.write_text("import time\nprint('before timeout', flush=True)\ntime.sleep(30)\n")
            second.write_text("print('other suite completed')\n")
            result = self.invoke(root, ((str(first), 1), (str(second), 3)))
            self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
            self.assertIn("exit 124", result.stdout)
            self.assertIn("before timeout", result.stdout)
            self.assertIn("other suite completed", result.stdout)

    def invoke(self, directory: Path, suites: tuple[tuple[str, float], ...]) -> subprocess.CompletedProcess[str]:
        """Bound the runner itself so a regression cannot hang the test process."""
        return subprocess.run(
            [sys.executable, "-c", f"import sys; sys.path.insert(0, {str(ROOT)!r}); "
             "from tools.run_independent_suites import run_suites; "
             f"raise SystemExit(run_suites({suites!r}))"],
            cwd=directory, capture_output=True, text=True, timeout=10)


if __name__ == "__main__":
    unittest.main()
