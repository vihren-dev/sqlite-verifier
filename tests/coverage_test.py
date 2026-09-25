"""Verify report denominators and fail-closed treatment of missing conformance evidence."""

from pathlib import Path
import json
import hashlib
from copy import deepcopy
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
from coverage_atuin import PAYLOAD_CASES, RUNNER_CASES, SOURCE_ID, TARGET_SHA256, scope_report


def atuin_rows(root: Path, payload: bool) -> list[dict[str, object]]:
    """Tiny matching receipt fixtures exercise validation without rerunning native proofs."""
    rows = []
    folder = root / ("build/atuin-model-payload" if payload else "build/atuin-runner-model")
    folder.mkdir(parents=True, exist_ok=True)
    for case in PAYLOAD_CASES if payload else RUNNER_CASES:
        row = {"case":case, "schema_objects":10, "target_sql_sha256":TARGET_SHA256,
               "grammar_profile":"3.46.0", "native_source_id":SOURCE_ID}
        if payload:
            count = case.split("-")[1]
            native, proof = folder/f"native-{count}.json", folder/f"Payload{count}.lean"
            names = {"checkedHistory", "checkedConformance"}
            row.update(scope="payload-history-and-schema", grammar_profile="3.46.0",
                native_status="REAL_SQLX_RUNNER_MATCHED_INDEPENDENT_EXPECTATIONS",
                model_status="KERNEL_CHECKED_CONCRETE_ASSERTIONS", native_source_id=SOURCE_ID,
                full_runner_relation="NOT_YET_COMPARED",
                non_history_model_rows="abstracted empty; payload does not inspect them")
        else:
            native, proof = folder/f"{case}.json", folder/f"{case}.lean"
            names = {"checkedTrace", "checkedReady", "before_conforms"}
            row.update(scope="complete captured tables, physical rows, metadata and statistics",
                model_status="KERNEL_CHECKED_PROFILE_EXECUTES", unmodified_profile_failure_claim=False,
                native_configuration="unmodified runner" if case=="success" else "authorizer-fault-instrumented",
                metadata_rowids={"before":list(range(1,7)), "post_close":list(range(1,8))},
                statistics_rows={stage:{"sqlite_stat1":6,"sqlite_stat4":0} for stage in ("before","post_close")})
        native.write_text(case); proof.write_text(case+" proof")
        row.update(axioms={name:["propext"] for name in names},
                   native_trace_sha256=hashlib.sha256(native.read_bytes()).hexdigest(),
                   proof_sha256=hashlib.sha256(proof.read_bytes()).hexdigest())
        rows.append(row)
    return rows


class CoverageTest(unittest.TestCase):
    """Reporting must preserve unavailable evidence rather than fabricate zero discrepancies."""

    def test_single_fresh_invocation_ignores_old_report(self) -> None:
        """A prior success file cannot replace failed fresh comparisons or cause a rerun."""
        with TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "build").mkdir()
            (root / "build/coverage.json").write_text(json.dumps({
                "status": "EVIDENCE_CHECKS_PASSED", "native_model": {"observed_discrepancies": 0}}))
            with patch("coverage_report.command", return_value={"status": "FAILED"}) as runner:
                report = collect(root, "selected-native")
            commands = [call.args[0] for call in runner.call_args_list]
        for script in ("tests/parser_test.py", "tests/conformance_native_test.py",
                       "tests/conformance_model_test.py", "tests/conformance_atuin_model_test.py",
                       "tests/conformance_atuin_runner_model_test.py"):
            self.assertEqual(sum(script in command for command in commands), 1, commands)
        self.assertFalse(any("conformance/model_check.py" in command for command in commands))
        self.assertEqual(report["status"], "EVIDENCE_CHECKS_FAILED")
        self.assertIsNone(report["native_model"]["observed_discrepancies"])
        self.assertIsNone(report["atuin"]["payload"]["observed_discrepancies"])
        self.assertIsNone(report["atuin"]["runner"]["observed_discrepancies"])

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
            if any(name.endswith("conformance_model_test.py") for name in arguments):
                return {"status": "PASSED", "stdout": "[]"}
            if any(name.endswith("conformance_native_test.py") for name in arguments):
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
            if any(name.endswith("conformance_model_test.py") for name in arguments):
                return {"status": "PASSED", "stdout": json.dumps(derived)}
            if any(name.endswith("conformance_native_test.py") for name in arguments):
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

    def test_atuin_scope_completeness_and_receipts(self) -> None:
        """Separate exact scopes reject duplicates, altered claims and mismatched retained bytes."""
        with TemporaryDirectory() as temporary:
            root = Path(temporary)
            for payload in (True, False):
                rows = atuin_rows(root, payload)
                good = {"status":"PASSED", "stdout":json.dumps(rows)}
                report = scope_report(root, good, payload=payload)
                self.assertEqual(report["completed_matching_cases"], 3 if payload else 2)
                if not payload:
                    self.assertEqual(report["fault_instrumented_case_denominator"], 1)
                    self.assertEqual(report["unmodified_native_failure_coverage"], "NOT_ESTABLISHED")
                variants = [[], rows[:-1], [rows[0]]*len(rows)]
                for field, value in (("target_sql_sha256", "0"*64), ("proof_sha256", "0"*64),
                        ("model_status", "unchecked"), ("scope", "universal"), ("axioms", {}),
                        ("native_source_id", "unbound"), ("grammar_profile", "3.51.0")):
                    altered = deepcopy(rows); altered[0][field] = value; variants.append(altered)
                if not payload:
                    for field, value in (("unmodified_profile_failure_claim", True),
                            ("native_configuration", "unmodified runner"), ("metadata_rowids", {})):
                        altered = deepcopy(rows); altered[1][field] = value; variants.append(altered)
                for value in variants:
                    with self.subTest(payload=payload, value=value):
                        evidence = {"status":"PASSED", "stdout":json.dumps(value)}
                        failed = scope_report(root, evidence, payload=payload)
                        self.assertEqual(evidence["status"], "FAILED")
                        self.assertIsNone(failed["completed_matching_cases"])
                        self.assertIsNone(failed["observed_discrepancies"])
                stale = {"status":"FAILED", "stdout":json.dumps(rows)}
                self.assertIsNone(scope_report(root, stale, payload=payload)["observed_discrepancies"])
                next((root/("build/atuin-model-payload" if payload else "build/atuin-runner-model")).glob("*.lean")).unlink()
                self.assertEqual(scope_report(root, good, payload=payload)["status"], "FAILED")

    def test_commands_fail_boundedly(self) -> None:
        """Both unavailable tools and timed-out tools yield explicit reportable failure."""
        self.assertEqual(command(["/definitely/missing/coverage-tool"], ROOT, 1)["status"], "FAILED")
        self.assertEqual(command([sys.executable, "-c", "import time; time.sleep(3)"], ROOT, 1)["status"], "FAILED")


if __name__ == "__main__":
    unittest.main()
