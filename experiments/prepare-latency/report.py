"""Print Markdown median tables from profile_data_path.py or prototypes.py JSON lines.

Usage: python3 experiments/prepare-latency/report.py FILE.jsonl [FILE.jsonl ...]
"""

from collections import defaultdict
from dataclasses import dataclass
import json
from pathlib import Path
from statistics import median
import sys

STAGES = ("lean_compile", "lean_deps", "export", "bundle_checker", "lean_probe")
"""Child-process groups shown as columns; `python_s` is the remainder of the wall time."""


@dataclass(frozen=True)
class Stage:
    """Number of child processes in one group and their summed wall time."""

    count: int
    seconds: float


@dataclass(frozen=True)
class Run:
    """One measured command, decoded and type-checked from a JSON line."""

    options: str
    case: str
    scenario: str
    status: str
    total: float
    python: float
    stages: dict[str, Stage]

    @classmethod
    def decode(cls, line: str) -> "Run":
        """Validate one JSON line; a wrong type raises ValueError that names the field to correct."""
        record: object = json.loads(line)
        if not isinstance(record, dict):
            raise invalid("the record", "a JSON object", line)
        return cls(text(record, "options", line, "none"), text(record, "case", line),
                   text(record, "scenario", line), text(record, "status", line),
                   number(record, "total_s", line), number(record, "python_s", line), stages(record, line))


def invalid(field: str, expected: str, line: str) -> ValueError:
    """Error that names the field, the expected type and the line to correct."""
    return ValueError(f"In the input JSON lines, {field} must be {expected}: {line[:80]}. "
                      "Correct the line or measure again, then run the report again.")


def text(record: dict[object, object], field: str, line: str, default: str | None = None) -> str:
    """A string field; `default` applies only when the field is absent."""
    value = record.get(field, default)
    if not isinstance(value, str):
        raise invalid(f"field {field}", "a string", line)
    return value


def number(record: dict[object, object], field: str, line: str) -> float:
    """A numeric field, excluding booleans."""
    value = record.get(field)
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise invalid(f"field {field}", "a number", line)
    return float(value)


def stages(record: dict[object, object], line: str) -> dict[str, Stage]:
    """The `stages` object: each name maps to an integer `count` and a numeric `s`."""
    value = record.get("stages")
    if not isinstance(value, dict):
        raise invalid("field stages", "a JSON object", line)
    decoded: dict[str, Stage] = {}
    for name, stage in value.items():
        if not isinstance(name, str) or not isinstance(stage, dict):
            raise invalid(f"stage {name}", "a JSON object", line)
        count = stage.get("count")
        if isinstance(count, bool) or not isinstance(count, int):
            raise invalid(f"stages.{name}.count", "an integer", line)
        decoded[name] = Stage(count, number(stage, "s", line))
    return decoded


def table(runs: list[Run]) -> list[str]:
    """Group by options, case and scenario; one row of medians per group."""
    groups: dict[tuple[str, str, str], list[Run]] = defaultdict(list)
    for run in runs:
        groups[(run.options, run.case, run.scenario)].append(run)
    lines = ["| Options | Case | Scenario | Status | Total s | Python s | "
             + " | ".join(f"{stage} s (n)" for stage in STAGES) + " |",
             "|" + " --- |" * (6 + len(STAGES))]
    for (options, case, scenario), group in groups.items():
        statuses = "/".join(sorted({run.status for run in group}))
        cells = []
        for name in STAGES:
            stages = [run.stages.get(name, Stage(0, 0.0)) for run in group]
            cells.append(f"{median(s.seconds for s in stages):.2f} ({median(s.count for s in stages):g})")
        lines.append(f"| {options} | {case} | {scenario} | {statuses} | {median(r.total for r in group):.2f} | "
                     f"{median(r.python for r in group):.2f} | " + " | ".join(cells) + " |")
    return lines


if __name__ == "__main__":
    print("\n".join(table([Run.decode(line) for path in sys.argv[1:]
                           for line in Path(path).read_text(encoding="utf-8").splitlines()])))
