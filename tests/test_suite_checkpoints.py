"""Reject checkpoint identities that could mislabel an interrupted suite's selected cases."""

import json
from pathlib import Path

import pytest

from tests.case_reports import RunReports

pytestmark = [pytest.mark.unit, pytest.mark.environment]


@pytest.mark.parametrize("field", ["runtime", "suite", "run_id", "selected_node_ids", "malformed"])
def test_invalid_suite_checkpoint_retains_failure(tmp_path: Path, field: str) -> None:
    """Wrong runtime, suite, run or selection remains diagnostic bytes and cannot supply case phases."""
    node = "tests/test_probe.py::test_probe"
    reports = RunReports(tmp_path, "source", "probe", "current")
    checkpoint = {"runtime": "source", "suite": "probe", "run_id": "current", "selected_node_ids": [node]}
    checkpoint[field] = ["wrong::node"] if field == "selected_node_ids" else "wrong"
    original = "not JSON" if field == "malformed" else json.dumps(checkpoint)
    artifacts = reports.suite_artifacts()
    artifacts.mkdir(parents=True)
    (artifacts / "selection.json").write_text(original)
    reports.interrupted((node,), 124, "outer timeout", 1.0, True)
    result = json.loads((tmp_path / "source/probe.json").read_text())
    assert result["exit_code"] == 124 and result["timed_out"]
    assert result["selected_node_ids"] == [node] and result["selection_status"] == "requested"
    assert result["cases"] == [{"node_id": node, "phases": {}}]
    assert "Selection checkpoint unavailable" in result["diagnostic"]
    assert (artifacts / "selection.json").read_text() == original
    assert reports.suite_artifacts() != RunReports(tmp_path, "installed", "probe", "current").suite_artifacts()
    assert reports.suite_artifacts() != RunReports(tmp_path, "source", "other", "current").suite_artifacts()
