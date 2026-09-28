"""Bound pytest suites, overlapping only the audited kernel/CLI pair."""

from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
import sys
from time import monotonic
from uuid import uuid4

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from tests.runtime_support import CommandTimeout, run_command

SUITES = (("tests/kernel_gate_test.py", 360), ("tests/cli_test.py", 600))


def run_suite(script: str, timeout: float, logs: Path, arguments: tuple[str, ...],
              selection: tuple[str, ...]) -> tuple[Path, int, float]:
    """Kill the entire pytest process group at its deadline and retain both streams."""
    started = monotonic()
    log = logs / (Path(script).stem + ".log")
    try:
        try:
            result = run_command([sys.executable, "-m", "pytest", *selection, *arguments,
                                  "--suite", Path(script).stem],
                                 cwd=Path.cwd(), timeout=timeout,
                                 artifacts=logs / Path(script).stem)
            code = result.returncode
        except CommandTimeout as error:
            result, code = error.result, 124
        log.write_text(result.stdout + result.stderr)
    except OSError as error:
        log.write_text(str(error) + "\n")
        code = 1
    return log, code, monotonic() - started


def run_suites(suites: tuple[tuple[str, float], ...] = SUITES, *,
               max_workers: int | None = None, runtime_root: Path | None = None,
               run_id: str | None = None, pytest_args: tuple[str, ...] = (),
               selections: dict[str, tuple[str, ...]] | None = None) -> int:
    """Await all siblings on failure; every launch shares explicit runtime and run identity."""
    max_workers = max_workers or (2 if sys.platform == "linux" else 1)
    logs = Path("build/test-logs")
    logs.mkdir(parents=True, exist_ok=True)
    arguments = ("-v", "--durations=20", "--runtime-root", str(runtime_root or Path.cwd()),
                 "--runtime-variant", "source", "--run-id", run_id or str(uuid4()), *pytest_args)
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
            futures[workers.submit(run_suite, script, timeout, logs, arguments, selection)] = script
        for future in as_completed(futures):
            log, code, elapsed = future.result()
            print(f"=== {futures[future]}: exit {code}, {elapsed:.2f}s; log {log} ===", flush=True)
            print(log.read_text(errors="replace"), end="", flush=True)
            failed |= code != 0
    print(f"Independent suites: {monotonic() - started:.2f}s total", flush=True)
    return int(failed)


if __name__ == "__main__":
    raise SystemExit(run_suites())
