"""Require independent native observations and kernel-checked payload expectations."""
from pathlib import Path
import json
import subprocess
import sys
from tempfile import TemporaryDirectory
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "conformance"))
from atuin_cases import lean_rows
from atuin_model_check import run


class PayloadModelTest(unittest.TestCase):
    """The real runner, grammar admission and model must agree on all three fixtures."""

    def test_observations_and_false_expected_rows(self) -> None:
        """An incorrect expected nonempty result must fail kernel checking."""
        reports = run(ROOT / "build/sqlite-parser-3.46.0")
        self.assertEqual([report["case"] for report in reports],
                         ["history-0-rows", "history-1-rows", "history-3-rows"])
        self.assertTrue(all(report["full_runner_relation"] == "NOT_YET_COMPARED" for report in reports))
        (ROOT / "build/atuin-model-payload.json").write_text(json.dumps(reports, indent=2) + "\n")
        source = (ROOT / "build/atuin-model-payload/Payload3.lean").read_text()
        needle = "rows := " + lean_rows(3, after=True)
        self.assertEqual(source.count(needle), 1)
        with TemporaryDirectory(prefix="atuin-negative-proof-") as directory:
            proof = Path(directory) / "IncorrectExpectation.lean"
            proof.write_text(source.replace(needle, "rows := []"))
            checked = subprocess.run(["lake", "env", "lean", str(proof)], cwd=ROOT,
                                     capture_output=True, text=True, timeout=45)
            self.assertNotEqual(checked.returncode, 0)
            self.assertIn("decide", checked.stdout)


if __name__ == "__main__":
    unittest.main()
