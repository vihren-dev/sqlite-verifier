"""Summarize P1 results and apply ADR 0003's decision rule.

Usage: python3 experiments/adr-0003-latency/p1_report.py RESULTS.jsonl [...] > report.md

Medians use warm trials. Rule (ADR 0003, "P1 measurements and decision rule"):
required comparisons are the data path's edit-to-result time against tuning's, for
proof-only and SQL changes, for every example, on macOS and Linux, compared within
each contract state. A regression is any measured cell where an option is slower
than today's `verify` for the same example, change and time. Correctness requires
every trial to report its example's expected status.
"""

from collections import defaultdict
import json
from pathlib import Path
from statistics import median
import sys

REQUIRED_PLATFORMS = ("Darwin", "Linux")
THRESHOLD = 0.30
Cell = tuple[str, str, str, str, str]


def load(paths: list[Path]) -> list[dict[str, object]]:
    """Read every JSON line from every results file."""
    return [json.loads(line) for path in paths for line in path.read_text().splitlines() if line.strip()]


def summarize(rows: list[dict[str, object]]) -> dict[Cell, dict[str, float | None]]:
    """Warm medians and cold values per platform, scenario, change, option and state."""
    grouped: dict[Cell, list[dict[str, object]]] = defaultdict(list)
    for row in rows:
        host = row["host"]
        assert isinstance(host, dict)
        grouped[(str(host["system"]), str(row["scenario"]), str(row["change"]), str(row["option"]),
                 str(row["state"]))].append(row)
    summary: dict[Cell, dict[str, float | None]] = {}
    for cell, trials in grouped.items():
        values: dict[str, float | None] = {}
        for metric in ("acceptance_s", "edit_to_result_s"):
            warm = [float(t[metric]) for t in trials if not t["cold"] and t[metric] is not None]
            cold = [float(t[metric]) for t in trials if t["cold"] and t[metric] is not None]
            values[metric] = median(warm) if warm else None
            values["cold_" + metric] = cold[0] if cold else None
        summary[cell] = values
    return summary


def outcome(rows: list[dict[str, object]], summary: dict[Cell, dict[str, float | None]]) -> list[str]:
    """Apply the ordered decision rule and explain each finding."""
    notes: list[str] = []
    wrong = [r for r in rows if r["status"] != r["expected"]]
    correctness = {option: not any(r["option"] == option for r in wrong) for option in ("tuning", "data")}
    platforms = {cell[0] for cell in summary}
    missing = [p for p in REQUIRED_PLATFORMS if p not in platforms]
    regressions: dict[str, list[str]] = {"tuning": [], "data": []}
    for (system, scenario, change, option, state), values in summary.items():
        if option == "today":
            continue
        today = summary.get((system, scenario, change, "today", "fresh"), {})
        for metric in ("acceptance_s", "edit_to_result_s"):
            ours, base = values.get(metric), today.get(metric)
            if ours is not None and base is not None and ours > base:
                regressions[option].append(f"{system}/{scenario}/{change}/{state}/{metric}")
    ratios: list[tuple[str, float]] = []
    for (system, scenario, change, option, state), values in summary.items():
        if option != "data" or change not in ("proof", "sql"):
            continue
        tuning = summary.get((system, scenario, change, "tuning", state), {}).get("edit_to_result_s")
        data = values.get("edit_to_result_s")
        if tuning and data is not None:
            ratios.append((f"{system}/{scenario}/{change}/{state}", 1 - data / tuning))
    notes.append(f"Correctness: tuning {'passes' if correctness['tuning'] else 'FAILS'}, "
                 f"data path {'passes' if correctness['data'] else 'FAILS'} ({len(wrong)} wrong statuses).")
    notes.append("Regressions against today: " + json.dumps(regressions))
    notes.append("Data-path edit-to-result improvement over tuning: " +
                 ", ".join(f"{name} {ratio:+.0%}" for name, ratio in sorted(ratios)))
    if missing:
        notes.append(f"Outcome: OPEN. Missing platform results: {', '.join(missing)}.")
        return notes
    both_correct = correctness["tuning"] and correctness["data"]
    if both_correct and not regressions["data"] and ratios and all(r >= THRESHOLD for _, r in ratios):
        notes.append("Outcome: ADOPT THE DATA PATH.")
    elif both_correct and not regressions["data"] and ratios and all(r > 0 for _, r in ratios):
        notes.append("Outcome: OWNER DECISION (data path faster everywhere, below 30% somewhere).")
    elif correctness["tuning"] and not regressions["tuning"]:
        notes.append("Outcome: SHIP TUNING.")
    else:
        notes.append("Outcome: KEEP THE CURRENT PATH (tuning failed correctness or regressed).")
    return notes


def table(summary: dict[Cell, dict[str, float | None]]) -> list[str]:
    """Markdown table of warm medians with cold values in parentheses."""
    def show(values: dict[str, float | None], metric: str) -> str:
        warm, cold = values.get(metric), values.get("cold_" + metric)
        return "—" if warm is None else f"{warm:.2f} ({cold:.2f})" if cold is not None else f"{warm:.2f}"
    lines = ["| Platform | Example | Change | Option | Contract | Acceptance s | Edit to result s |",
             "| --- | --- | --- | --- | --- | --- | --- |"]
    order = {"today": 0, "tuning": 1, "data": 2}
    for cell in sorted(summary, key=lambda c: (c[0], c[1], c[2], order[c[3]], c[4])):
        values = summary[cell]
        lines.append("| " + " | ".join(cell) + f" | {show(values, 'acceptance_s')} | {show(values, 'edit_to_result_s')} |")
    return lines


def main() -> None:
    """Print the Markdown report for the given result files."""
    rows = load([Path(argument) for argument in sys.argv[1:]])
    summary = summarize(rows)
    print("\n".join(["# ADR 0003 P1 results", "", "Warm medians; cold first trial in parentheses.", "",
                     *table(summary), "", "## Decision rule", "", *(f"- {note}" for note in outcome(rows, summary))]))


if __name__ == "__main__":
    main()
