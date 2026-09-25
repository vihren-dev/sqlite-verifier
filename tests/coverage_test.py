"""Verify report denominators and fail-closed treatment of missing conformance evidence."""

from pathlib import Path
import json
from collections.abc import Sequence
import sys
from tempfile import TemporaryDirectory
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "conformance"))
from coverage_catalog import THEOREMS
from coverage_evidence import command, structured
from coverage_report import collect
from model_cases import cases


class CoverageTest(unittest.TestCase):
    """Reporting must preserve unavailable evidence rather than fabricate zero discrepancies."""

    def test_failed_evidence_keeps_counts_separate(self) -> None:
        """A failed runner leaves comparison counts unknown while import denominators remain exact."""
        with TemporaryDirectory() as temporary, patch("coverage_report.command", return_value={"status": "FAILED"}):
            report = collect(Path(temporary), "missing-native")
        self.assertEqual(report["status"], "EVIDENCE_CHECKS_FAILED")
        self.assertIsNone(report["native_model"]["observed_discrepancies"])
        self.assertIsNone(report["native_model"]["completed_matching_cases"])
        self.assertEqual(report["native_model"]["authored_case_denominator"], len(cases()))
        self.assertEqual(report["proofs"]["status"], "NOT_RUN")
        self.assertEqual(report["proofs"]["denominator"], len(THEOREMS))
        imported = report["upstream_fixtures"]
        self.assertEqual((imported["selected_call_instances"], imported["upstream_textual_call_sites"]), (3, 59))
        self.assertEqual((imported["selected_distinct_ids"], imported["upstream_distinct_textual_ids"]), (2, 55))
        self.assertEqual(imported["model_status"], "NOT_YET_MODEL_CHECKED")
        self.assertIsNone(report["documented_claims"]["sqlite_documentation_total"])
        self.assertEqual(report["grammar"]["production_execution_coverage"], "NOT_INSTRUMENTED")
        self.assertIsNone(report["additional_grammars"]["3.46.0"]["generated_productions"])

    def test_incomplete_reports_are_not_passing_coverage(self) -> None:
        """Exit-zero JSON cannot substitute for the selected case set."""
        def incomplete(arguments: Sequence[str], root: Path, timeout: int) -> dict[str, object]:
            """Supply well-formed but incomplete runner output without running external tools."""
            if any(name.endswith("model_check.py") for name in arguments):
                return {"status": "PASSED", "stdout": "[]"}
            if any(name.endswith("native_fixture.py") for name in arguments):
                return {"status": "PASSED", "stdout": "{}"}
            return {"status": "FAILED"}
        with TemporaryDirectory() as temporary, patch("coverage_report.command", side_effect=incomplete):
            report = collect(Path(temporary), "unused")
        self.assertEqual(report["checks"]["derived_native_model"]["status"], "FAILED")
        self.assertEqual(report["checks"]["upstream_native"]["status"], "FAILED")
        self.assertIsNone(report["native_model"]["observed_discrepancies"])

    def test_duplicate_success_rows_do_not_count(self) -> None:
        """Correct lengths and status labels cannot manufacture complete case coverage."""
        derived = [{"case": cases()[0].name, "native_status": "MATCHES_INDEPENDENT_EXPECTATION",
                    "grammar_status": "PARSED", "translation_status": "PRODUCTION_PIPELINE",
                    "model_status": "KERNEL_CHECKED_CONCRETE_ASSERTIONS"}] * len(cases())
        upstream = {"cases": [{"upstream_id": "alter3-3.1", "occurrence": 1,
                              "native_status": "MATCHES_UPSTREAM", "grammar_status": "PARSED"}] * 3}
        def duplicated(arguments: Sequence[str], root: Path, timeout: int) -> dict[str, object]:
            """Return repeated successful observations with the expected list lengths."""
            if any(name.endswith("model_check.py") for name in arguments):
                return {"status": "PASSED", "stdout": json.dumps(derived)}
            if any(name.endswith("native_fixture.py") for name in arguments):
                return {"status": "PASSED", "stdout": json.dumps(upstream)}
            return {"status": "FAILED"}
        with TemporaryDirectory() as temporary, patch("coverage_report.command", side_effect=duplicated):
            report = collect(Path(temporary), "unused")
        self.assertEqual(report["checks"]["derived_native_model"]["status"], "FAILED")
        self.assertEqual(report["checks"]["upstream_native"]["status"], "FAILED")
        self.assertIsNone(report["native_model"]["observed_discrepancies"])
        self.assertIsNone(report["native_model"]["completed_matching_cases"])

    def test_bad_json_is_failure(self) -> None:
        """An exit-zero process without valid evidence cannot count as a passing observation."""
        evidence = {"status": "PASSED", "stdout": "not JSON"}
        self.assertIsNone(structured(evidence))
        self.assertEqual(evidence["status"], "FAILED")

    def test_commands_fail_boundedly(self) -> None:
        """Both unavailable tools and timed-out tools yield explicit reportable failure."""
        self.assertEqual(command(["/definitely/missing/coverage-tool"], ROOT, 1)["status"], "FAILED")
        self.assertEqual(command([sys.executable, "-c", "import time; time.sleep(3)"], ROOT, 1)["status"], "FAILED")


if __name__ == "__main__":
    unittest.main()
