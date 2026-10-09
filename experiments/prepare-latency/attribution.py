"""Pure wall-time attribution for the prepare-latency scripts.

Child processes can run at the same time (the `parallel` prototype), so the time
spent waiting on children is the union of their intervals, not the sum.
"""

from collections.abc import Iterable

Interval = tuple[float, float]
"""Start and end of one child process, in `time.perf_counter()` seconds."""


def covered_seconds(intervals: Iterable[Interval]) -> float:
    """Return the length of the union of the intervals; overlapping time counts once."""
    covered, reach = 0.0, float("-inf")
    for start, end in sorted(intervals):
        if end <= reach:
            continue
        covered += end - max(start, reach)
        reach = end
    return covered


def python_remainder(total: float, intervals: Iterable[Interval]) -> float:
    """Wall time of a command that no child process covers: the orchestration's own time."""
    return total - covered_seconds(intervals)
