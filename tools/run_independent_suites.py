"""Bound pytest suites, overlapping only the audited kernel/CLI pair."""

from concurrent.futures import ThreadPoolExecutor, as_completed
import argparse
from pathlib import Path
import sys
from time import monotonic
from uuid import uuid4

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from tests.runtime_support import CommandTimeout, run_command
from tests.case_reports import RunReports

SUITES = (("tests/kernel_gate_test.py", 360), ("tests/cli_test.py", 600))


def run_suite(script: str, timeout: float, logs: Path, arguments: tuple[str, ...],
              selection: tuple[str, ...], context: RunReports) -> tuple[Path, int, float]:
    """Kill the entire pytest process group at its deadline and retain both streams."""
    started = monotonic()
    suite = Path(script).stem
    log = logs / f"{context.runtime}-{suite}.log"
    reports = [context.directory / context.runtime / f"{suite}.{suffix}" for suffix in ("json", "xml")]
    for path in reports:
        path.unlink(missing_ok=True)
    artifacts = context.suite_artifacts()
    (artifacts / "selection.json").unlink(missing_ok=True)
    timed_out = False
    try:
        try:
            result = run_command([sys.executable, "-m", "pytest", *selection, *arguments,
                                  "--suite", suite],
                                 cwd=Path.cwd(), timeout=timeout,
                                 artifacts=artifacts)
            code = result.returncode
        except CommandTimeout as error:
            result, code = error.result, 124
            timed_out = True
        log.write_text(result.stdout + result.stderr)
        diagnostic = result.diagnostic()
    except OSError as error:
        diagnostic = str(error)
        log.write_text(diagnostic + "\n")
        code = 1
    if not all(path.is_file() for path in reports):
        code = code or 1
        diagnostic += "\nPytest did not produce both suite JSON and JUnit reports."
    if timed_out or not all(path.is_file() for path in reports):
        context.interrupted(selection, code, diagnostic, monotonic() - started, timed_out)
    return log, code, monotonic() - started


def run_suites(suites: tuple[tuple[str, float], ...] = SUITES, *,
               max_workers: int | None = None, runtime_root: Path | None = None,
               run_id: str | None = None, pytest_args: tuple[str, ...] = (),
               selections: dict[str, tuple[str, ...]] | None = None,
               report_dir: Path = Path("build/test-results"), runtime_variant: str = "source",
               runtime_archive: Path | None = None) -> int:
    """Await all siblings on failure; every launch shares explicit runtime and run identity."""
    if runtime_archive is not None and (runtime_root is not None or runtime_variant != "installed"):
        raise ValueError("An archive requires installed runtime and no separate runtime root")
    max_workers = max_workers or (2 if sys.platform == "linux" else 1)
    logs = Path("build/test-logs")
    logs.mkdir(parents=True, exist_ok=True)
    run_id = run_id or str(uuid4())
    runtime_arguments = (("--runtime-archive", str(runtime_archive)) if runtime_archive is not None
                         else ("--runtime-root", str(runtime_root or Path.cwd())))
    arguments = ("-v", "--durations=20", *pytest_args, *runtime_arguments,
                 "--runtime-variant", runtime_variant, "--run-id", run_id,
                 "--report-dir", str(report_dir))
    started = monotonic()
    failed = False
    print(f"Independent suites: {max_workers} worker(s)", flush=True)
    with ThreadPoolExecutor(max_workers=max_workers) as workers:
        futures = {}
        for script, timeout in suites:
            selection = selections[script] if selections is not None else (script,)
            if not selection:
                continue
            print(f"Scheduling {script} (timeout {timeout}s)", flush=True)
            context = RunReports(report_dir.absolute(), runtime_variant, Path(script).stem, run_id)
            futures[workers.submit(run_suite, script, timeout, logs, arguments, selection, context)] = script
        for future in as_completed(futures):
            log, code, elapsed = future.result()
            print(f"=== {futures[future]}: exit {code}, {elapsed:.2f}s; log {log} ===", flush=True)
            print(log.read_text(errors="replace"), end="", flush=True)
            failed |= code != 0
    print(f"Independent suites: {monotonic() - started:.2f}s total", flush=True)
    return int(failed)


def main() -> int:
    """Apply the shared watchdog to one explicitly selected smoke or installed invocation."""
    if len(sys.argv) == 1:
        return run_suites()
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--timeout", type=float, required=True)
    parser.add_argument("--suite", required=True)
    parser.add_argument("--runtime-variant", choices=("source", "installed"), default="source")
    parser.add_argument("--runtime-root", type=Path)
    parser.add_argument("--runtime-archive", type=Path)
    parser.add_argument("--report-dir", type=Path, default=Path("build/test-results"))
    parser.add_argument("selection", nargs=argparse.REMAINDER)
    options = parser.parse_args()
    selection = tuple(options.selection[1:] if options.selection[:1] == ["--"] else options.selection)
    if not selection or options.timeout <= 0:
        parser.error("A positive timeout and pytest selection are required")
    return run_suites(((options.suite, options.timeout),), max_workers=1,
                      runtime_variant=options.runtime_variant, runtime_root=options.runtime_root,
                      runtime_archive=options.runtime_archive, report_dir=options.report_dir,
                      selections={options.suite: selection})


if __name__ == "__main__":
    raise SystemExit(main())
