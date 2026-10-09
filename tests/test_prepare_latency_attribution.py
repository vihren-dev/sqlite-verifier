"""Wall-time attribution in experiments/prepare-latency counts overlapping child processes once."""

import importlib.util
from pathlib import Path
from types import ModuleType

import pytest

ROOT = Path(__file__).resolve().parents[1]
pytestmark = pytest.mark.unit


def attribution() -> ModuleType:
    """Load the pure attribution module from the experiment directory, whose name is not a package."""
    specification = importlib.util.spec_from_file_location(
        "prepare_latency_attribution", ROOT / "experiments/prepare-latency/attribution.py")
    assert specification is not None and specification.loader is not None
    module = importlib.util.module_from_spec(specification)
    specification.loader.exec_module(module)
    return module


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
    """Three overlapping 2 s children inside a 2.5 s command leave 0.5 s of orchestration time."""
    remainder = attribution().python_remainder(2.5, [(0.25, 2.25), (0.25, 2.25), (0.5, 2.0)])
    assert remainder == pytest.approx(0.5)
