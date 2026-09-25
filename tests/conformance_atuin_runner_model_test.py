"""Validate full finite runner traces and reject corrupted bookkeeping expectations."""
import json
from pathlib import Path
import subprocess
import sys
from tempfile import TemporaryDirectory
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "conformance"))
from atuin_runner_model_check import run


class RunnerModelTest(unittest.TestCase):
    """Complete native metadata/statistics participate in each checked runner outcome."""

    def test_complete_traces_and_false_metadata(self) -> None:
        """An inserted version changed after observation cannot satisfy the runner relation."""
        reports = run()
        self.assertEqual([row["case"] for row in reports], ["success", "timing_authorizer_failure"])
        self.assertEqual([row["native_configuration"] for row in reports],
                         ["unmodified runner", "authorizer-fault-instrumented"])
        for report in reports:
            self.assertEqual(report["model_status"], "KERNEL_CHECKED_PROFILE_EXECUTES")
            self.assertEqual(report["metadata_rowids"],
                             {"before":list(range(1,7)), "post_close":list(range(1,8))})
            self.assertEqual(set(report["axioms"]), {"checkedTrace", "checkedReady", "before_conforms"})
            self.assertFalse(report["unmodified_profile_failure_claim"])
        source = (ROOT / "build/atuin-runner-model/success.lean").read_text()
        prefix, tail = source.split("def afterMetadata : Table :=", 1)
        declaration, suffix = tail.split("theorem afterMetadata_valid", 1)
        self.assertEqual(declaration.count("20260709214605"), 1)
        incorrect = prefix + "def afterMetadata : Table :=" + declaration.replace(
            "20260709214605", "20260709214606") + "theorem afterMetadata_valid" + suffix
        with TemporaryDirectory(prefix="atuin-false-metadata-") as directory:
            proof = Path(directory) / "IncorrectMetadata.lean"
            proof.write_text(incorrect)
            result = subprocess.run(["lake", "env", "lean", str(proof)], cwd=ROOT,
                                    capture_output=True, text=True, timeout=60)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("decide", result.stdout)
        (ROOT / "build/atuin-runner-model.json").write_text(json.dumps(reports, indent=2) + "\n")
        print(json.dumps(reports, indent=2))


if __name__ == "__main__":
    unittest.main()
