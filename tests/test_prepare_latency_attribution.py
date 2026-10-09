"""experiments/prepare-latency: attribution counts overlapping children once; the report validates input."""

import importlib.util
import json
from pathlib import Path
from types import ModuleType

import pytest

ROOT = Path(__file__).resolve().parents[1]
pytestmark = pytest.mark.unit


def experiment(name: str) -> ModuleType:
    """Load a side-effect-free module from the experiment directory, whose name is not a package."""
    specification = importlib.util.spec_from_file_location(
        f"prepare_latency_{name}", ROOT / f"experiments/prepare-latency/{name}.py")
    assert specification is not None and specification.loader is not None
    module = importlib.util.module_from_spec(specification)
    specification.loader.exec_module(module)
    return module


def attribution() -> ModuleType:
    """The pure attribution module."""
    return experiment("attribution")


@pytest.mark.parametrize("intervals,covered", [
    ([], 0.0),
    ([(0.0, 1.0), (2.0, 3.0)], 2.0),
    ([(0.0, 2.0), (1.0, 3.0)], 3.0),
    ([(1.0, 3.0), (0.0, 4.0), (2.0, 2.5)], 4.0),
    ([(0.0, 1.0), (1.0, 2.0)], 2.0),
])
def test_covered_seconds_counts_overlap_once(intervals: list[tuple[float, float]], covered: float) -> None:
    """Concurrent compiles in the `parallel` prototype must not push the Python remainder below zero."""
    assert attribution().covered_seconds(intervals) == pytest.approx(covered)


def test_python_remainder_with_concurrent_children_is_not_negative() -> None:
    """`attribution.python_remainder`: overlapping 2 s children in a 2.5 s command leave 0.5 s."""
    remainder = attribution().python_remainder(2.5, [(0.25, 2.25), (0.25, 2.25), (0.5, 2.0)])
    assert remainder == pytest.approx(0.5)


VALID = {"case": "small", "scenario": "prepare_noop", "status": "PREPARED", "total_s": 1.2, "python_s": 0.3,
         "stages": {"export": {"count": 1, "s": 0.4}}}
"""A minimal valid line as profile_data_path.py writes it (no `options` field)."""


def test_report_decode_accepts_harness_record() -> None:
    """`report.Run.decode` reads a harness line and defaults `options` to the baseline name."""
    run = experiment("report").Run.decode(json.dumps(VALID))
    assert (run.options, run.total, run.stages["export"].count, run.stages["export"].seconds) == ("none", 1.2, 1, 0.4)


@pytest.mark.parametrize("change,field", [
    ({"total_s": "1.2"}, "field total_s"),
    ({"case": 3}, "field case"),
    ({"stages": []}, "field stages"),
    ({"stages": {"export": {"count": True, "s": 0.4}}}, "stages.export.count"),
    ({"stages": {"export": {"count": 1, "s": None}}}, "field s"),
])
def test_report_decode_names_invalid_field(change: dict[str, object], field: str) -> None:
    """`report.Run.decode` refuses wrong types, including nested stage fields, and names the field."""
    with pytest.raises(ValueError, match=f"{field} must be"):
        experiment("report").Run.decode(json.dumps({**VALID, **change}))
