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
        """Validate one JSON line; a wrong type raises ValueError that names the field."""
        record: object = json.loads(line)
        if not isinstance(record, dict) or not isinstance(record.get("stages"), dict):
            raise ValueError(f"Run record is not an object with a stages object: {line[:80]}")
        text = {key: record.get(key, "none" if key == "options" else None)
                for key in ("options", "case", "scenario", "status")}
        numbers = {key: record.get(key) for key in ("total_s", "python_s")}
        for key, value in text.items():
            if not isinstance(value, str):
                raise ValueError(f"Field {key} must be a string in: {line[:80]}")
        for key, value in numbers.items():
            if not isinstance(value, (int, float)):
                raise ValueError(f"Field {key} must be a number in: {line[:80]}")
        stages = {name: Stage(int(value["count"]), float(value["s"])) for name, value in record["stages"].items()}
        return cls(str(text["options"]), str(text["case"]), str(text["scenario"]), str(text["status"]),
                   float(numbers["total_s"]), float(numbers["python_s"]), stages)  # type: ignore[arg-type]


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
