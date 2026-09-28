"""Check actual child overlap, complete diagnostics, deadlines and joined failures."""

import pytest

import os
from pathlib import Path
import subprocess
import sys
import textwrap
from tempfile import TemporaryDirectory
import unittest

ROOT = Path(__file__).resolve().parents[1]


class IndependentSuiteTests(unittest.TestCase):
    """Use child rendezvous instead of machine-speed assertions to prove overlap."""

    @pytest.mark.integration
    @pytest.mark.environment
    @pytest.mark.requires_native("/bin/ps")
    def test_overlap_failure_join_and_timeout(self) -> None:
        """A failing or timed-out sibling cannot hide the other's completed output."""
        with TemporaryDirectory() as temporary:
            root = Path(temporary).resolve()
            first, second = root / "first.py", root / "second.py"
            for exit_code in (0, 7):
                with self.subTest(exit_code=exit_code):
                    first.write_text(
                        "from pathlib import Path\nimport time, sys\n"
                        "Path('first-ready').touch()\n"
                        "while not Path('second-ready').exists(): time.sleep(0.01)\n"
                        "print('first stdout')\nprint('first stderr', file=sys.stderr)\n"
                        "Path('first-finished').touch()\n"
                        f"assert {exit_code} == 0\n")
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
                        log = (root / "build/test-logs" / f"source-{name}.log").read_text()
                        self.assertIn(f"{name} stdout", log)
                        self.assertIn(f"{name} stderr", log)
                        self.assertIn(log, result.stdout)
                    self.assertIn(f"exit {int(exit_code != 0)}", result.stdout)
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

    @pytest.mark.integration
    @pytest.mark.environment
    def test_serial_mode_finishes_failed_first_suite_before_second(self) -> None:
        """The macOS fallback still runs the next suite after a completed failure."""
        with TemporaryDirectory() as temporary:
            root = Path(temporary).resolve()
            first, second = root / "first.py", root / "second.py"
            first.write_text("from pathlib import Path\nimport time\ntime.sleep(0.2)\n"
                             "Path('first-finished').touch()\nraise SystemExit(7)\n")
            second.write_text("from pathlib import Path\nassert Path('first-finished').exists()\n"
                              "print('second ran after first finished')\n")
            result = self.invoke(root, ((str(first), 3), (str(second), 3)), max_workers=1)
            self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
            self.assertIn("exit 1", result.stdout)
            self.assertIn("exit 0", result.stdout)
            self.assertIn("second ran after first finished", result.stdout)

    def invoke(self, directory: Path, suites: tuple[tuple[str, float], ...], *,
               max_workers: int = 2) -> subprocess.CompletedProcess[str]:
        """Bound the runner itself so a regression cannot hang the test process."""
        (directory / "conftest.py").write_text(
            "import json\nfrom pathlib import Path\n"
            "def pytest_addoption(parser):\n"
            "    for option in ('runtime-root', 'runtime-variant', 'suite', 'run-id', 'report-dir'):\n"
            "        parser.addoption('--' + option)\n"
            "def pytest_sessionfinish(session):\n"
            "    config=session.config\n"
            "    path=Path(config.getoption('report_dir'))/'source'\n"
            "    path.mkdir(parents=True,exist_ok=True)\n"
            "    for suffix, content in (('json','{}'),('xml','<testsuites/>')):\n"
            "        (path/(config.getoption('suite')+'.'+suffix)).write_text(content)\n")
        for script, _ in suites:
            path = Path(script)
            path.write_text("def test_scenario():\n" + textwrap.indent(path.read_text(), "    "))
        return subprocess.run(
            [sys.executable, "-c", f"import sys; sys.path.insert(0, {str(ROOT)!r}); "
             "from tools.run_independent_suites import run_suites; "
             f"raise SystemExit(run_suites({suites!r}, max_workers={max_workers}, pytest_args=('-s',)))"],
            cwd=directory, capture_output=True, text=True, timeout=10,
            env={**os.environ, "PYTHONDONTWRITEBYTECODE": "1"})


if __name__ == "__main__":
    unittest.main()
