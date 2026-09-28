"""Compare three native repetitions without enabling build-cache rollout automatically."""

import argparse
import itertools
import json
from pathlib import Path
from statistics import median
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from tools.benchmark_evidence import collect

SYSTEMS = ("aarch64-darwin", "x86_64-linux")
SCENARIOS = ("cold", "warm", "python", "lean", "package")


def summarize(samples: list[dict]) -> dict:
    """Require complete successful evidence before comparing warm improvement and cold cost."""
    expected = set(itertools.product(("baseline", "candidate"), SYSTEMS, (1, 2, 3), SCENARIOS))
    identities = [(row["variant"], row["system"], row["replica"], row["scenario"]) for row in samples]
    errors = []
    if len(identities) != len(set(identities)) or set(identities) != expected:
        errors.append("Expected exactly 60 unique native samples")
    for sample in samples:
        label = sample["job_name"]
        if sample.get("exit_code") != 0 or sample.get("conclusion") != "success":
            errors.append(label + ": correctness gate failed")
        if not sample.get("disk"):
            errors.append(label + ": missing disk observation through cache post hook")
        restored = sample.get("cache", {}).get("RESTORED_KEY") or ""
        hit = bool(restored) and (restored == sample["cache_key"] or
                                 bool(sample["cache_prefix"]) and restored.startswith(sample["cache_prefix"]))
        if (sample["scenario"] == "cold" and restored) or (sample["scenario"] != "cold" and not hit):
            errors.append(label + ": unexpected cold/warm cache state")
        if sample["variant"] == "candidate":
            reports = sample.get("case_reports", [])
            cached = sample.get("cached_test_reports", [])
            source_ids = [case["node_id"] for report in reports if report.get("runtime") == "source"
                          for case in report.get("cases", [])]
            cached_ids = [case["node_id"] for report in cached for case in report.get("cases", [])]
            installed_ids = [case["node_id"] for report in reports if report.get("runtime") == "installed"
                             for case in report.get("cases", [])]
            combined = source_ids + cached_ids
            if (not sample.get("source_ids") or len(combined) != len(set(combined)) or
                    set(combined) != set(sample["source_ids"]) or cached_ids != sample.get("cached_ids")):
                errors.append(label + ": source/cache selection differs from exact catalogue")
            if not sample.get("source_run_id") or any(
                    report.get("run_id") != sample["source_run_id"] for report in reports
                    if report.get("runtime") == "source"):
                errors.append(label + ": missing or stale fresh source run identity")
            if sample["scenario"] == "package" and (
                    len(installed_ids) != 19 or len(set(installed_ids)) != 19 or
                    set(installed_ids) != set(sample.get("installed_ids", []))):
                errors.append(label + ": installed selection differs from exact 19-case inventory")
            runtimes = {report.get("runtime") for report in reports if report.get("cases")}
            required = {"source", "installed"} if sample["scenario"] == "package" else {"source"}
            if not required <= runtimes:
                errors.append(label + ": missing actual candidate case receipts")
            for report in reports + cached:
                if report.get("exit_code") != 0:
                    errors.append(label + ": failed case report")
                for case in report.get("cases", []):
                    phases = case.get("phases", {})
                    if set(phases) != {"setup", "call", "teardown"} or any(
                            phase["outcome"] != "passed" for phase in phases.values()):
                        errors.append(label + ": incomplete/nonpassing case " + case["node_id"])
    medians = {}
    for variant, system, scenario in itertools.product(("baseline", "candidate"), SYSTEMS, SCENARIOS):
        values = [row["total_seconds"] for row in samples
                  if (row["variant"], row["system"], row["scenario"]) == (variant, system, scenario)]
        if len(values) == 3:
            medians[f"{variant}/{system}/{scenario}"] = median(values)
    performance = {}
    if not errors:
        for system in SYSTEMS:
            performance[system] = {
                "warm_improves": medians[f"candidate/{system}/warm"] < medians[f"baseline/{system}/warm"],
                "cold_within_assumed_limit": medians[f"candidate/{system}/cold"] <=
                1.10 * medians[f"baseline/{system}/cold"],
            }
    return {"errors": errors, "median_job_seconds": medians, "performance": performance,
            "cold_regression_assumption": "At most 10% median slowdown; review assumption, not a spec amendment",
            "ready_for_review": not errors and all(all(row.values()) for row in performance.values()),
            "rollout_enabled": False, "samples": samples}


def main() -> None:
    """Keep raw artifacts and a machine-readable recommendation even when the experiment fails."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("evidence", type=Path)
    parser.add_argument("output", type=Path)
    arguments = parser.parse_args()
    arguments.output.mkdir(parents=True, exist_ok=True)
    summary = summarize(collect(arguments.evidence, arguments.output))
    (arguments.output / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    if not summary["ready_for_review"]:
        raise SystemExit("Benchmark incomplete or performance gates not met; inspect summary.json")


if __name__ == "__main__":
    main()
