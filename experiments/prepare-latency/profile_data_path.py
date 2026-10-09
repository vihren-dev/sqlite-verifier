"""Attribute `prepare` and `verify-bundle` wall time to child processes and Python.

Usage: python3 experiments/prepare-latency/profile_data_path.py [TRIALS] > out.jsonl

The verifier code is imported from `build/runtime` (the complete runtime that `just
build` links) or from `PREPARE_LATENCY_RUNTIME`; the examples come from this checkout.

Runs in-process so every child process launch can be timed; whatever is left of a
command's wall time after subtracting child processes is Python orchestration
(argument parsing, hashing, file copies, temporary directories). Each scenario
runs on fresh copies of the checked-in examples under build/prepare-latency/.
"""

from collections.abc import Callable, Sequence
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time

sys.path.insert(0, str(Path(__file__).resolve().parent))
from attribution import Interval, python_remainder  # noqa: E402

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "adr-0003-latency"))
from cases import CASES, ROOT, ExampleCase  # noqa: E402

RUNTIME = Path(os.environ.get("PREPARE_LATENCY_RUNTIME", ROOT / "build" / "runtime")).resolve()
"""Installed runtime whose launcher, libraries and Python package are measured."""
sys.path.insert(0, str(RUNTIME))
from migration_check import bundle, cli, process, source_closure  # noqa: E402
from migration_check.diagnostics import Rejection  # noqa: E402

WORK = ROOT / "build" / "prepare-latency"
"""Scratch copies, agent workspaces, bundles and stage stores."""

EVENTS: list[tuple[str, Interval]] = []
"""(label, (start, end)) for every child process of the current command."""

COMPILES: list[tuple[str, float]] = []
"""(module file stem, seconds) for every Lean compile of the current command."""


def label(command: Sequence[str]) -> str:
    """Classify a child process by its command line."""
    executable = Path(command[0]).name
    if "--deps-json" in command:
        return "lean_deps"
    if "--version" in command or "--print-prefix" in command:
        return "lean_probe"
    if executable == "lean":
        return "lean_compile"
    if "exporter" in executable:
        return "export"
    if "bundle-checker" in executable:
        return "bundle_checker"
    if "parser" in executable:
        return "sql_parser"
    return executable


def recorded(original: Callable[..., object]) -> Callable[..., object]:
    """Wrap a process launcher so each call's start and end land in EVENTS."""
    def run(command: Sequence[object], *arguments: object, **keywords: object) -> object:
        """Delegate unchanged and record elapsed time, including failures."""
        started = time.perf_counter()
        try:
            return original(command, *arguments, **keywords)
        finally:
            parts = [str(part) for part in command]
            ended = time.perf_counter()
            seconds = ended - started
            EVENTS.append((label(parts), (started, ended)))
            if label(parts) == "lean_compile":
                COMPILES.append((Path(parts[-1]).stem, round(seconds, 3)))
    return run


timed_run_process = recorded(process.run_process)
source_closure.run_process = timed_run_process
bundle.run_process = timed_run_process
subprocess.run = recorded(subprocess.run)


def summary(command: Callable[[], dict[str, object]]) -> dict[str, object]:
    """Run one command and report total, per-label child time and the Python remainder.

    Per-label times are sums, so with concurrent children they can exceed the total;
    the Python remainder subtracts the union of child intervals instead.
    """
    EVENTS.clear()
    COMPILES.clear()
    started = time.perf_counter()
    try:
        status = str(command()["status"])
    except Rejection as rejection:
        status = rejection.status
    total = time.perf_counter() - started
    stages: dict[str, list[float]] = {}
    for key, (begin, end) in EVENTS:
        stages.setdefault(key, []).append(end - begin)
    remainder = python_remainder(total, (interval for _, interval in EVENTS))
    return {"status": status, "total_s": round(total, 3), "python_s": round(remainder, 3),
            "compiles": COMPILES.copy(),
            "stages": {key: {"count": len(values), "s": round(sum(values), 3)} for key, values in stages.items()}}


def fresh_copy(case: ExampleCase, trial: int) -> tuple[ExampleCase, Path]:
    """Copy the example's inputs so edits and workspaces never touch the checkout."""
    base = WORK / f"{case.name}-{trial}"
    shutil.rmtree(base, ignore_errors=True)
    shutil.copytree(case.approved, base / "approved")
    shutil.copytree(case.candidate, base / "candidate", ignore=shutil.ignore_patterns("approved"))
    shutil.copy(case.schema, base / "schema.sql")
    return ExampleCase(case.name, base / "schema.sql", base / "approved", base / "candidate",
                       case.profile, case.theorem), base


def contract_arguments(case: ExampleCase) -> list[str]:
    """Inputs shared by `prepare` and `verify-bundle`."""
    return ["--profile", case.profile, "--format", "json", "--schema", str(case.schema),
            "--requirements", str(case.approved / "Requirements.lean"),
            "--interpretation", str(case.approved / "Interpretation.lean"),
            "--migration", str(case.candidate / "migration.sql")]


def scenarios(case: ExampleCase, base: Path) -> list[tuple[str, Callable[[], dict[str, object]]]]:
    """Ordered scenarios; later ones rely on state left by earlier ones."""
    from migration_check.bundle import verify_bundle
    from migration_check.prepare import prepare

    output = base / "proof.bundle"
    prepare_options = cli.arguments(["prepare", *contract_arguments(case),
                                     "--next-interpretation", str(case.candidate / "NextInterpretation.lean"),
                                     "--proofs", str(case.candidate / "Proofs.lean"),
                                     "--workspace", str(base / "agent"), "--output", str(output)])
    bundle_options = cli.arguments(["verify-bundle", *contract_arguments(case), "--bundle", str(output)])

    def proof_edit() -> dict[str, object]:
        """Change Proofs.lean bytes without changing its meaning, then prepare."""
        with (case.candidate / "Proofs.lean").open("a", encoding="utf-8") as stream:
            stream.write(f"\n-- edit {time.time_ns()}\n")
        return prepare(prepare_options)

    def with_store() -> dict[str, object]:
        """verify-bundle with the opt-in stage store (approved reuse measurement override).

        The first call fills the empty store; the second call restores from it.
        """
        os.environ["MIGRATION_CHECK_STAGE_STORE"] = str(base / "store")
        os.environ["MIGRATION_CHECK_MEASUREMENT_APPROVED_REUSE"] = "1"
        try:
            return verify_bundle(bundle_options)
        finally:
            del os.environ["MIGRATION_CHECK_STAGE_STORE"], os.environ["MIGRATION_CHECK_MEASUREMENT_APPROVED_REUSE"]

    return [("prepare_cold", lambda: prepare(prepare_options)),
            ("prepare_noop", lambda: prepare(prepare_options)),
            ("prepare_proof_edit", proof_edit),
            ("verify_bundle", lambda: verify_bundle(bundle_options)),
            ("verify_bundle_store_fill", with_store),
            ("verify_bundle_store_warm", with_store)]


if __name__ == "__main__":
    trials = int(sys.argv[1]) if len(sys.argv) > 1 else 3
    for case in CASES:
        for trial in range(trials):
            copy, base = fresh_copy(case, trial)
            for name, command in scenarios(copy, base):
                print(json.dumps({"case": case.name, "trial": trial + 1, "scenario": name,
                                  **summary(command)}), flush=True)
