"""Reject stale or incomplete producer receipts even when successful-looking files remain."""

import hashlib
import json
from pathlib import Path
import sys

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "conformance"))
from coverage_receipts import Receipts
from coverage_receipts import checks_from_receipts

pytestmark = [pytest.mark.unit, pytest.mark.conformance]
NODE = "tests/coverage_evidence_test.py::test_proof_build"


@pytest.fixture
def receipt_tree(tmp_path: Path) -> tuple[Path, Path, dict[str, object]]:
    """Construct one complete, internally consistent source receipt with no runtime tools."""
    source = tmp_path / "source"
    digest = hashlib.sha256(json.dumps(["source", NODE]).encode()).hexdigest()
    artifacts = source / "artifacts" / digest / "current"
    artifacts.mkdir(parents=True)
    (artifacts / "case.json").write_text(json.dumps({"runtime": "source", "node_id": NODE, "run_id": "current"}))
    (artifacts / "receipt.json").write_text('{"status":"PASSED"}')
    report = {"runtime": "source", "run_id": "current", "exit_code": 0,
              "cases": [{"node_id": NODE, "artifacts": str(artifacts),
                "phases": {phase: {"outcome": "passed", "timed_out": False}
                           for phase in ("setup", "call", "teardown")}}]}
    (source / "suite.json").write_text(json.dumps(report))
    return source, artifacts, report


def test_current_complete_receipt_is_read_once(receipt_tree: tuple[Path, Path, dict[str, object]]) -> None:
    """Complete fresh phases and matching directory metadata permit the original evidence value."""
    source, _, _ = receipt_tree
    assert Receipts(source, "current").data(NODE, "receipt.json") == {"status": "PASSED"}


@pytest.mark.parametrize("mutation", ["old-run", "installed", "missing-phase", "skip", "timeout",
    "failed-suite", "duplicate", "old-path", "wrong-metadata", "missing-receipt", "bad-json"])
def test_invalid_receipts_fail_closed(receipt_tree: tuple[Path, Path, dict[str, object]], mutation: str) -> None:
    """Old, repeated or failed evidence cannot supply a current success despite leftover receipt bytes."""
    source, artifacts, report = receipt_tree
    case = report["cases"][0]
    if mutation == "old-run":
        report["run_id"] = "old"
    elif mutation == "installed":
        report["runtime"] = "installed"
    elif mutation == "missing-phase":
        del case["phases"]["teardown"]
    elif mutation == "skip":
        case["phases"]["call"]["outcome"] = "skipped"
    elif mutation == "timeout":
        case["phases"]["call"]["timed_out"] = True
    elif mutation == "failed-suite":
        report["exit_code"] = 1
    elif mutation == "duplicate":
        (source / "duplicate.json").write_text(json.dumps(report))
    elif mutation == "old-path":
        case["artifacts"] = str(artifacts.parent / "old")
    elif mutation == "wrong-metadata":
        (artifacts / "case.json").write_text('{}')
    elif mutation == "missing-receipt":
        (artifacts / "receipt.json").unlink()
    elif mutation == "bad-json":
        (artifacts / "receipt.json").write_text('not json')
    (source / "suite.json").write_text(json.dumps(report))
    with pytest.raises((ValueError, OSError)):
        Receipts(source, "current").data(NODE, "receipt.json")


@pytest.mark.parametrize("value", [[], None, {"run_id": "current", "runtime": "source", "cases": [None]}],
                         ids=["list", "null", "invalid-cases"])
def test_malformed_report_still_yields_failure_checks(tmp_path: Path, value: object) -> None:
    """Malformed report shapes become failed evidence rather than aborting report generation."""
    (tmp_path / "suite.json").write_text(json.dumps(value))
    checks = checks_from_receipts(tmp_path, tmp_path, "current")
    assert checks and all(check["status"] == "FAILED" for check in checks.values())
    assert all("Case report must" in str(check["diagnostic"]) for check in checks.values())
