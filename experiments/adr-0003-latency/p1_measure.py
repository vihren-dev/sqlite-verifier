"""ADR 0003 P1: measure today's `verify`, tuning and the data path over the decision matrix.

Usage (inside the dev shell, after `just build` in both roots):
  python3 experiments/adr-0003-latency/p1_measure.py --baseline-root ../base-checkout \
      --output build/adr-0003-p1/$(uname -s)-$(uname -m).jsonl [--warm 5] [--scenario small]

`--baseline-root` is a checkout of the revision before P1 (today's `verify`); this
repository supplies tuning and the data path. Each cell starts from fresh copies, an
empty stage store and an empty agent workspace: its first trial is recorded as cold,
the rest as warm. Operating-system file caches are not dropped.
"""

import argparse
import json
import os
import platform
from pathlib import Path
import shutil
import subprocess
import sys
import time

sys.path.insert(0, str(Path(__file__).resolve().parent))
from cases import ROOT, WORK  # noqa: E402
from p1_cases import CHANGES, SCENARIOS, Copy, Scenario, apply_edit, materialize  # noqa: E402

STORE, OVERRIDE = "MIGRATION_CHECK_STAGE_STORE", "MIGRATION_CHECK_MEASUREMENT_APPROVED_REUSE"
OPTIONS = (("today", "fresh"), ("tuning", "fresh"), ("tuning", "reused"), ("data", "fresh"), ("data", "reused"))


def run(command: list[str], environment: dict[str, str]) -> tuple[float, dict[str, object]]:
    """Time one public command and decode its JSON report."""
    started = time.perf_counter()
    result = subprocess.run(command, env=environment, capture_output=True, text=True, timeout=600, check=False)
    elapsed = time.perf_counter() - started
    try:
        report = json.loads(result.stdout)
    except ValueError:
        report = {"status": "NO_REPORT", "message": (result.stdout + result.stderr)[-2000:]}
    return elapsed, report


def trial(option: str, state: str, scenario: Scenario, copy: Copy, cell: Path, baseline: Path) -> dict[str, object]:
    """One measurement: acceptance time and edit-to-result time for the selected option."""
    environment = dict(os.environ)
    environment.pop(OVERRIDE, None)
    environment.pop(STORE, None)
    if option != "today":
        environment[STORE] = str(cell / "stage-store")
        if state == "reused":
            environment[OVERRIDE] = "1"
    root = baseline if option == "today" else ROOT
    launcher = [sys.executable, "-I", str(root / "bin/migration-check")]
    arguments = copy.arguments(scenario.profile)
    if option != "data":
        seconds, report = run([*launcher, "verify", *arguments, *copy.candidate_arguments()], environment)
        return {"acceptance_s": seconds, "edit_to_result_s": seconds, "status": report.get("status")}
    bundle = cell / "proof.bundle"
    prepare_s, prepared = run([*launcher, "prepare", *arguments, *copy.candidate_arguments(),
                               "--workspace", str(cell / "agent"), "--output", str(bundle)], environment)
    if prepared.get("status") != "PREPARED":
        return {"acceptance_s": None, "edit_to_result_s": prepare_s, "status": prepared.get("status"),
                "prepare_s": prepare_s, "message": prepared.get("message")}
    seconds, report = run([*launcher, "verify-bundle", *arguments, "--bundle", str(bundle)], environment)
    return {"acceptance_s": seconds, "edit_to_result_s": prepare_s + seconds, "status": report.get("status"),
            "prepare_s": prepare_s, "compiled_modules": prepared.get("compiled_modules")}


def cells(scenarios: tuple[Scenario, ...]) -> list[tuple[Scenario, str, str, str]]:
    """The ADR matrix; a contract edit always compiles a fresh contract."""
    return [(scenario, change, option, state) for scenario in scenarios for change in CHANGES
            for option, state in OPTIONS if change != "contract" or state == "fresh"]


def main() -> None:
    """Run every selected cell and append one JSON line per trial."""
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--baseline-root", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--warm", type=int, default=5)
    parser.add_argument("--scenario", action="append", choices=[s.name for s in SCENARIOS])
    options = parser.parse_args()
    selected = tuple(s for s in SCENARIOS if not options.scenario or s.name in options.scenario)
    host = {"system": platform.system(), "machine": platform.machine(), "node": platform.node()}
    revision = "unknown"
    for command in (["git", "rev-parse", "HEAD"], ["jj", "log", "--no-graph", "-r", "@-", "-T", "commit_id"]):
        try:
            found = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, timeout=10, check=False)
        except OSError:
            continue
        if found.returncode == 0 and found.stdout.strip():
            revision = found.stdout.strip()
            break
    options.output.parent.mkdir(parents=True, exist_ok=True)
    with options.output.open("a") as stream:
        for scenario, change, option, state in cells(selected):
            cell = WORK / "p1" / f"{scenario.name}-{change}-{option}-{state}"
            shutil.rmtree(cell, ignore_errors=True)
            copy = materialize(scenario, cell / "examples")
            for index in range(options.warm + 1):
                apply_edit(scenario, copy, change, index)
                row = {"host": host, "revision": revision, "scenario": scenario.name, "change": change,
                       "option": option, "state": state, "trial": index, "cold": index == 0,
                       "expected": scenario.expected,
                       **trial(option, state, scenario, copy, cell, options.baseline_root.resolve())}
                stream.write(json.dumps(row) + "\n")
                stream.flush()
                print(json.dumps({k: row[k] for k in ("scenario", "change", "option", "state", "trial",
                                                     "status", "acceptance_s", "edit_to_result_s")}), flush=True)


if __name__ == "__main__":
    main()
