"""Cached evidence cannot admit resources, omitted cases or skipped execution phases."""

import importlib.util
from pathlib import Path

import pytest

pytestmark = [pytest.mark.unit, pytest.mark.environment]


@pytest.mark.parametrize("variant", [
    "passing_catalogue", "passing_execution", "resource", "non_unit", "wrong_id",
    "missing_phases", "setup_only", "skipped_call", "failed_teardown", "omitted_case", "duplicate_case",
])
def test_unit_cache_requires_exact_resource_free_completed_cases(variant: str) -> None:
    """Both pre-execution catalogue and successful-report validation fail closed on drift."""
    path = Path(__file__).resolve().parents[1] / "build-support/run_unit_checks.py"
    specification = importlib.util.spec_from_file_location("run_unit_checks", path)
    assert specification is not None and specification.loader is not None
    runner = importlib.util.module_from_spec(specification)
    specification.loader.exec_module(runner)
    case = {"node_id": "tests/test_fake.py::test_case", "level": "unit", "resources": [],
            "phases": {name: {"outcome": "passed"} for name in ("setup", "call", "teardown")}}
    expected = [case["node_id"]]
    variants = {
        "passing_catalogue": [case], "passing_execution": [case],
        "resource": [{**case, "resources": ["requires_nix"]}],
        "non_unit": [{**case, "level": "integration"}],
        "wrong_id": [{**case, "node_id": "unreviewed"}],
        "missing_phases": [{**case, "phases": {}}],
        "setup_only": [{**case, "phases": {"setup": {"outcome": "passed"}}}],
        "skipped_call": [{**case, "phases": {**case["phases"], "call": {"outcome": "skipped"}}}],
        "failed_teardown": [{**case, "phases": {**case["phases"], "teardown": {"outcome": "failed"}}}],
        "omitted_case": [], "duplicate_case": [case, case],
    }
    executed = variant not in {"passing_catalogue", "resource", "non_unit", "wrong_id"}
    if variant.startswith("passing_"):
        runner.validate_cases(expected, variants[variant], executed=executed)
    else:
        with pytest.raises(ValueError):
            runner.validate_cases(expected, variants[variant], executed=executed)
