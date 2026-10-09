"""Print Markdown median tables from profile_data_path.py or prototypes.py JSON lines.

Usage: python3 experiments/prepare-latency/report.py FILE.jsonl [FILE.jsonl ...]
"""

from collections import defaultdict
import json
from pathlib import Path
from statistics import median
import sys

STAGES = ("lean_compile", "lean_deps", "export", "bundle_checker", "lean_probe")
"""Child-process groups shown as columns; `python_s` is the remainder of the wall time."""


def main(paths: list[str]) -> None:
    """Group by options, case and scenario; print medians of total, Python and each stage."""
    groups: dict[tuple[str, str, str], list[dict[str, object]]] = defaultdict(list)
    for path in paths:
        for line in Path(path).read_text(encoding="utf-8").splitlines():
            record = json.loads(line)
            groups[(str(record.get("options", "none")), record["case"], record["scenario"])].append(record)
    print("| Options | Case | Scenario | Status | Total s | Python s | "
          + " | ".join(f"{stage} s (n)" for stage in STAGES) + " |")
    print("|" + " --- |" * (6 + len(STAGES)))
    for (options, case, scenario), records in groups.items():
        statuses = sorted({str(record["status"]) for record in records})
        cells = []
        for stage in STAGES:
            values = [record["stages"].get(stage, {"s": 0.0, "count": 0}) for record in records]  # type: ignore[union-attr]
            cells.append(f"{median(v['s'] for v in values):.2f} ({median(v['count'] for v in values):g})")
        print(f"| {options} | {case} | {scenario} | {'/'.join(statuses)} | "
              f"{median(float(r['total_s']) for r in records):.2f} | "  # type: ignore[arg-type]
              f"{median(float(r['python_s']) for r in records):.2f} | " + " | ".join(cells) + " |")  # type: ignore[arg-type]


if __name__ == "__main__":
    main(sys.argv[1:])
