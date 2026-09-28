"""Verify report denominators and fail-closed treatment of missing conformance evidence."""

import pytest

from pathlib import Path
import json
import hashlib
from copy import deepcopy
import sys
from tempfile import TemporaryDirectory
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "conformance"))
from coverage_catalog import THEOREMS
from coverage_evidence import structured
from coverage_receipts import checks_from_receipts
from tests.runtime_support import CommandTimeout, run_command
from coverage_report import assemble
from model_cases import cases
from coverage_atuin import CASES, sql_report


def atuin_rows(root: Path) -> list[dict[str, object]]:
    """Construct native-only receipts bound to the exact example bytes."""
    folder = root / "examples/atuin"
    folder.mkdir(parents=True, exist_ok=True)
    (folder/"schema.sql").write_bytes(b"CREATE TABLE t(x);\r\n")
    (folder/"migration.sql").write_bytes(b"ALTER TABLE t ADD y;\r\n")
    return [{"case":case, "profile":"3.46.0",
        "status":"NATIVE_SQL_EXPECTATIONS_PASSED", "model_status":"NOT_COMPARED_BY_THIS_TEST",
        "schema_sha256":hashlib.sha256((folder/"schema.sql").read_bytes()).hexdigest(),
        "migration_sha256":hashlib.sha256((folder/"migration.sql").read_bytes()).hexdigest(),
        "domain":"old application data preservation"} for case in CASES]


def failed_checks() -> dict[str, dict[str, object]]:
    """Supply unavailable observations without executing or mocking a legacy runner."""
    return {name: {"status": "NOT_RUN" if name == "named_proofs" else "FAILED"} for name in (
        "proof_build", "parser_regressions", "upstream_native", "derived_native_model",
        "atuin_sql", "grammar_export", "grammar_346_export", "named_proofs")}


class CoverageTest(unittest.TestCase):
    """Reporting must preserve unavailable evidence rather than fabricate zero discrepancies."""

    @pytest.mark.unit
    @pytest.mark.conformance
    def test_single_fresh_invocation_ignores_old_report(self) -> None:
        """A prior success file cannot replace failed fresh comparisons or cause a rerun."""
        with TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "build").mkdir()
            (root / "build/coverage.json").write_text(json.dumps({
                "status": "EVIDENCE_CHECKS_PASSED", "native_model": {"observed_discrepancies": 0}}))
            (root / "tests").mkdir()
            (root / "tests/case-inventory.json").write_text('{"cases": []}\n')
            with patch("subprocess.Popen") as runner:
                report = assemble(root, checks_from_receipts(root, root / "reports", "current"))
            runner.assert_not_called()
            self.assertIn("Missing current-run phases", report["checks"]["proof_build"]["diagnostic"])
        self.assertEqual(report["status"], "EVIDENCE_CHECKS_FAILED")
        self.assertIsNone(report["native_model"]["observed_discrepancies"])
        self.assertIsNone(report["atuin_sql"]["observed_discrepancies"])

    @pytest.mark.unit
    @pytest.mark.conformance
    def test_failed_evidence_keeps_counts_separate(self) -> None:
        """A failed runner leaves comparison counts unknown while import denominators remain exact."""
        with TemporaryDirectory() as temporary:
            report = assemble(Path(temporary), failed_checks())
        self.assertEqual(report["status"], "EVIDENCE_CHECKS_FAILED")
        self.assertIsNone(report["native_model"]["observed_discrepancies"])
        self.assertIsNone(report["native_model"]["completed_matching_cases"])
        self.assertEqual(report["native_model"]["authored_case_denominator"], len(cases()))
        self.assertEqual(report["proofs"]["status"], "NOT_RUN")
        self.assertEqual(report["proofs"]["denominator"], len(THEOREMS))
        self.assertEqual(len(report["semantic_support"]["modeled_statement_forms"]), 5)
        self.assertFalse(report["semantic_support"]["inventory_is_coverage_denominator"])
        imported = report["upstream_fixtures"]
        self.assertEqual((imported["selected_call_instances"], imported["upstream_textual_call_sites"]), (3, 59))
        self.assertEqual((imported["selected_distinct_ids"], imported["upstream_distinct_textual_ids"]), (2, 55))
        self.assertEqual(imported["model_status"], "NOT_YET_MODEL_CHECKED")
        self.assertIsNone(report["documented_claims"]["sqlite_documentation_total"])
        self.assertEqual(report["grammar"]["production_execution_coverage"], "NOT_INSTRUMENTED")
        self.assertIsNone(report["additional_grammars"]["3.46.0"]["generated_productions"])

    @pytest.mark.unit
    @pytest.mark.conformance
    def test_incomplete_reports_are_not_passing_coverage(self) -> None:
        """Exit-zero JSON cannot substitute for the selected case set."""
        checks = failed_checks()
        checks["derived_native_model"] = {"status": "PASSED", "stdout": "[]"}
        checks["upstream_native"] = {"status": "PASSED", "stdout": "{}"}
        with TemporaryDirectory() as temporary:
            report = assemble(Path(temporary), checks)
        self.assertEqual(report["checks"]["derived_native_model"]["status"], "FAILED")
        self.assertEqual(report["checks"]["upstream_native"]["status"], "FAILED")
        self.assertIsNone(report["native_model"]["observed_discrepancies"])

    @pytest.mark.unit
    @pytest.mark.conformance
    def test_duplicate_success_rows_do_not_count(self) -> None:
        """Correct lengths and status labels cannot manufacture complete case coverage."""
        derived = [{"case": cases()[0].name, "native_status": "MATCHES_INDEPENDENT_EXPECTATION",
                    "grammar_status": "PARSED", "translation_status": "PRODUCTION_PIPELINE",
                    "model_status": "KERNEL_CHECKED_CONCRETE_ASSERTIONS"}] * len(cases())
        upstream = {"cases": [{"upstream_id": "alter3-3.1", "occurrence": 1,
                              "native_status": "MATCHES_UPSTREAM", "grammar_status": "PARSED"}] * 3}
        checks = failed_checks()
        checks["derived_native_model"] = {"status": "PASSED", "stdout": json.dumps(derived)}
        checks["upstream_native"] = {"status": "PASSED", "stdout": json.dumps(upstream)}
        with TemporaryDirectory() as temporary:
            report = assemble(Path(temporary), checks)
        self.assertEqual(report["checks"]["derived_native_model"]["status"], "FAILED")
        self.assertEqual(report["checks"]["upstream_native"]["status"], "FAILED")
        self.assertIsNone(report["native_model"]["observed_discrepancies"])
        self.assertIsNone(report["native_model"]["completed_matching_cases"])

    @pytest.mark.unit
    @pytest.mark.conformance
    def test_bad_json_is_failure(self) -> None:
        """An exit-zero process without valid evidence cannot count as a passing observation."""
        evidence = {"status": "PASSED", "stdout": "not JSON"}
        self.assertIsNone(structured(evidence))
        self.assertEqual(evidence["status"], "FAILED")

    @pytest.mark.unit
    @pytest.mark.conformance
    def test_atuin_sql_completeness_and_receipts(self) -> None:
        """Native-only cases reject duplicates, wrong bytes and inflated model claims."""
        with TemporaryDirectory() as temporary:
            root = Path(temporary)
            rows = atuin_rows(root)
            good = {"status":"PASSED", "stdout":json.dumps(rows)}
            report = sql_report(root, good)
            self.assertEqual(report["completed_matching_cases"], 3)
            variants = [[], rows[:-1], [rows[0]]*len(rows)]
            for field, value in (("schema_sha256", "0"*64), ("migration_sha256", "0"*64),
                    ("model_status", "KERNEL_CHECKED"), ("status", "FAILED"),
                    ("profile", "3.51.0"), ("domain", "universal")):
                altered = deepcopy(rows); altered[0][field] = value; variants.append(altered)
            for value in variants:
                with self.subTest(value=value):
                    evidence = {"status":"PASSED", "stdout":json.dumps(value)}
                    failed = sql_report(root, evidence)
                    self.assertEqual(evidence["status"], "FAILED")
                    self.assertIsNone(failed["completed_matching_cases"])
                    self.assertIsNone(failed["observed_discrepancies"])
            stale = {"status":"FAILED", "stdout":json.dumps(rows)}
            self.assertIsNone(sql_report(root, stale)["observed_discrepancies"])
            (root/"examples/atuin/schema.sql").unlink()
            self.assertEqual(sql_report(root, good)["status"], "FAILED")

    @pytest.mark.integration
    @pytest.mark.conformance
    def test_commands_fail_boundedly(self) -> None:
        """Both unavailable tools and timed-out tools yield explicit reportable failure."""
        with self.assertRaises(OSError):
            run_command(["/definitely/missing/coverage-tool"], cwd=ROOT, timeout=1)
        with self.assertRaises(CommandTimeout) as failure:
            run_command([sys.executable, "-c", "import time; time.sleep(3)"], cwd=ROOT, timeout=1)
        self.assertTrue(failure.exception.result.timed_out)
        self.assertNotEqual(failure.exception.result.returncode, 0)


if __name__ == "__main__":
    unittest.main()
