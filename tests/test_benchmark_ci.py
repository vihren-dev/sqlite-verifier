"""Benchmark comparisons reject incomplete evidence and preserve controlled source identities."""

import itertools
from pathlib import Path
from unittest.mock import patch
import subprocess

import pytest

from tools.benchmark_ci import BASELINE, prepare
from tools.benchmark_evidence import observations
from tools.benchmark_summary import SCENARIOS, SYSTEMS, summarize

pytestmark = [pytest.mark.unit, pytest.mark.environment]


def samples() -> list[dict]:
    """Produce a complete synthetic successful matrix, without executing native gates."""
    result = []
    for variant, system, replica, scenario in itertools.product(("baseline", "candidate"), SYSTEMS, (1, 2, 3), SCENARIOS):
        reports = [{"runtime": runtime, "exit_code": 0, "cases": [{"node_id": "tests/example.py::test_example",
                    "phases": {phase: {"outcome": "passed", "duration": 0.1}
                               for phase in ("setup", "call", "teardown")}}]}
                   for runtime in (("source", "installed") if scenario == "package" else ("source",))]
        for report in reports:
            report["run_id"] = "fresh"
            if report["runtime"] == "installed":
                report["cases"] = [{**report["cases"][0], "node_id": f"installed::{i}"} for i in range(19)]
        result.append({"variant": variant, "system": system, "replica": replica, "scenario": scenario,
                       "job_name": f"{variant}/{system}/{replica}/{scenario}", "exit_code": 0,
                       "conclusion": "success", "disk": {"workspace": {"peak_used_bytes": 1}},
                       "cache": {"RESTORED_KEY": "" if scenario == "cold" else "seed"},
                       "cache_key": "seed", "cache_prefix": "",
                       "source_ids": ["tests/example.py::test_example"], "cached_ids": [],
                       "source_run_id": "fresh", "installed_ids": [f"installed::{i}" for i in range(19)],
                       "total_seconds": 90 if variant == "candidate" else 100, "case_reports": reports})
    return result


def test_complete_benchmark_recommends_review_without_rollout() -> None:
    """Three measured repetitions on both platforms permit review, never automatic activation."""
    rows = samples()
    for row in rows:
        if row["scenario"] in {"python", "lean"}:
            row["cache_key"] = "seed-changed"
            row["cache_prefix"] = "seed"
    report = summarize(rows)
    assert report["ready_for_review"] and not report["rollout_enabled"]
    assert len(report["median_job_seconds"]) == 20


@pytest.mark.parametrize("problem", ["missing", "duplicate", "failed", "disk", "cache", "receipt", "phase", "slow", "catalogue", "stale", "installed"])
def test_benchmark_rejects_incomplete_or_regressed_matrix(problem: str) -> None:
    """Missing gates, stale cache assumptions and cold regressions cannot authorize rollout."""
    rows = samples()
    candidate = next(row for row in rows if row["variant"] == "candidate")
    if problem == "missing":
        rows.pop()
    elif problem == "duplicate":
        rows.append(rows[0])
    elif problem == "failed":
        rows[0]["exit_code"] = 1
    elif problem == "disk":
        rows[0]["disk"] = None
    elif problem == "cache":
        rows[0]["cache"]["RESTORED_KEY"] = "seed"
    elif problem == "receipt":
        candidate["case_reports"] = []
    elif problem == "phase":
        candidate["case_reports"][0]["cases"][0]["phases"]["call"]["outcome"] = "skipped"
    elif problem == "catalogue":
        candidate["source_ids"].append("missing::case")
    elif problem == "stale":
        candidate["source_run_id"] = "other-run"
    elif problem == "installed":
        next(row for row in rows if row["variant"] == "candidate" and row["scenario"] == "package")["installed_ids"] = []
    else:
        for row in rows:
            if row["variant"] == "candidate" and row["scenario"] == "cold":
                row["total_seconds"] = 111
    assert not summarize(rows)["ready_for_review"]


@pytest.mark.parametrize("scenario,path", [("python", "tests/test_translation.py"), ("lean", "SqliteVerifier/Model.lean")])
def test_baseline_controlled_mutation_is_recorded(tmp_path: Path, scenario: str, path: str) -> None:
    """Mutation changes only an explicit comment while preserving the reviewed baseline revision."""
    for name in ("nix/flake.nix", "nix/flake.lock", "nix/sqlite.nix", "lean-toolchain", path):
        target = tmp_path / name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text("original\n")
    with patch("tools.benchmark_ci.subprocess.run", return_value=subprocess.CompletedProcess([], 0, BASELINE)), \
         patch.dict("os.environ", {"GITHUB_RUN_ID": "123", "GITHUB_RUN_ATTEMPT": "2"}):
        report = prepare(tmp_path, "baseline", scenario, "aarch64-darwin", 1)
    assert report["mutation"]["before"] != report["mutation"]["after"]
    assert report["mutation"]["path"] == path
    assert (tmp_path / path).read_text().startswith("original\n")
    assert report["cache_key"].startswith("adr1-benchmark-123-2-baseline-aarch64-darwin-1-")


def test_job_observations_include_post_steps_and_honest_sizes() -> None:
    """Inclusive runner timing and disk markers survive after artifact upload/cache saving."""
    job = {"id": 7, "conclusion": "success", "started_at": "2026-09-28T00:00:00Z",
           "completed_at": "2026-09-28T00:02:00Z", "steps": [{"name": "Post Restore experiment store",
           "started_at": "2026-09-28T00:01:00Z", "completed_at": "2026-09-28T00:01:30Z"}]}
    report = observations(job, 'Cache Size: ~1 MB (123 B)\nADR1_DISK_METRICS={"workspace": {"peak_used_bytes": 456}}\n')
    assert report["total_seconds"] == 120 and report["cache_steps"][0]["seconds"] == 30
    assert report["reported_cache_bytes"] == [123]
    assert report["disk"]["workspace"]["peak_used_bytes"] == 456
    transfers = ("Cache Size: ~1 MB (123 B)\nReceived 123 of 123 (100.0%)\n"
                 "Sent 0 of 456 (0.0%)\nSent 455 of 456 (99.8%)\n"
                 "Sent 456 of 456 (100.0%)\nSent 456 of 456 (100.0%)\n"
                 "Received 789 of 789 (100.0%)\nReceived 789 of 789 (100.0%)\n"
                 "Received 12 of 999 (1.2%)\n")
    assert observations(job, transfers)["reported_cache_bytes"] == [123, 456, 789]
    assert observations(job, "") ["reported_cache_bytes"] == []
