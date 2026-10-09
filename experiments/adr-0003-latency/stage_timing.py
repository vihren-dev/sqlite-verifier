"""Attribute current `migration-check verify` wall time to SQL parsing, Lean processes and the gate.

Usage: python3 experiments/adr-0003-latency/stage_timing.py [TRIALS]
Prints one JSON line per trial. Refutations and refusals from the application
or SQL frontend are recorded as statuses so the remaining trials can run.
"""

from collections.abc import Callable, Sequence
import json
import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from cases import CASES, ROOT  # noqa: E402

sys.path.insert(0, str(ROOT))
from migration_check import cli, inputs, process  # noqa: E402
from migration_check import source_closure  # noqa: E402
from migration_check.diagnostics import Rejection  # noqa: E402
from belay.sqlite.errors import SqlError  # noqa: E402

EVENTS: list[tuple[str, float]] = []


def label(arguments: Sequence[str]) -> str:
    """Classify a bounded Lean process by its command line."""
    if arguments[0].endswith("migration-proof-checker"):
        return "gate"
    if "--deps-json" in arguments:
        return "dependencies"
    return "compile:" + Path(arguments[-1]).stem


def recorded(original: Callable[..., object], name: Callable[[object], str]) -> Callable[..., object]:
    """Wrap a process or parser call so its wall time is appended to EVENTS."""
    def run(first: object, *arguments: object, **keywords: object) -> object:
        """Delegate unchanged and record elapsed time, including failures."""
        started = time.perf_counter()
        try:
            return original(first, *arguments, **keywords)
        finally:
            EVENTS.append((name(first), time.perf_counter() - started))
    return run


def process_label(command: object) -> str:
    """Label a run_process call from its command sequence."""
    assert isinstance(command, Sequence)
    return label([str(part) for part in command])


source_closure.run_process = recorded(process.run_process, process_label)
cli.run_process = recorded(process.run_process, process_label)
inputs.parse = recorded(inputs.parse, lambda _parser: "sql_parse")


def trial(arguments: list[str]) -> dict[str, object]:
    """Run one in-process verification and group the recorded stage times."""
    EVENTS.clear()
    started = time.perf_counter()
    try:
        status = str(cli.verify(cli.arguments(arguments))["status"])
    except (Rejection, SqlError) as rejection:
        status = rejection.status
    total = time.perf_counter() - started
    stages: dict[str, float] = {}
    for key, seconds in EVENTS:
        stages[key] = stages.get(key, 0.0) + seconds
    compiles = [key for key, _ in EVENTS if key.startswith("compile:")]
    return {"status": status, "total_s": round(total, 2), "lean_compiles": len(compiles),
            "compile_s": round(sum(seconds for key, seconds in stages.items() if key.startswith("compile:")), 2),
            "gate_s": round(stages.get("gate", 0.0), 2), "stages_s": {k: round(v, 2) for k, v in stages.items()}}


if __name__ == "__main__":
    trials = int(sys.argv[1]) if len(sys.argv) > 1 else 3
    identity = subprocess.run(["uname", "-sm"], capture_output=True, text=True, check=True, timeout=5).stdout.strip()
    for case in CASES:
        for index in range(trials):
            print(json.dumps({"case": case.name, "trial": index + 1, "host": identity,
                              **trial(case.verify_arguments())}), flush=True)
