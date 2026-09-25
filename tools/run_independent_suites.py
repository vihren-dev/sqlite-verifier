"""Overlap only the audited kernel/CLI suites after their shared build completes."""

from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
import subprocess
import sys
from time import monotonic

SUITES = (("tests/kernel_gate_test.py", 360), ("tests/cli_test.py", 600))


def run_suite(script: str, timeout: float, logs: Path) -> tuple[Path, int, float]:
    """Keep the existing GNU timeout semantics and retain both streams without interleaving."""
    started = monotonic()
    log = logs / (Path(script).stem + ".log")
    with log.open("w") as output:
        try:
            result = subprocess.run(["timeout", str(timeout), sys.executable, "-u", script],
                                    stdout=output, stderr=subprocess.STDOUT)
            code = result.returncode
        except OSError as error:
            print(error, file=output)
            code = 1
    return log, code, monotonic() - started


def run_suites(suites: tuple[tuple[str, float], ...] = SUITES) -> int:
    """Await every suite even after failure, printing complete logs and measured durations."""
    logs = Path("build/test-logs")
    logs.mkdir(parents=True, exist_ok=True)
    started = monotonic()
    failed = False
    with ThreadPoolExecutor(max_workers=2) as workers:
        futures = {}
        for script, timeout in suites:
            print(f"Starting {script} (timeout {timeout}s)", flush=True)
            futures[workers.submit(run_suite, script, timeout, logs)] = script
        for future in as_completed(futures):
            log, code, elapsed = future.result()
            print(f"=== {futures[future]}: exit {code}, {elapsed:.2f}s; log {log} ===", flush=True)
            print(log.read_text(errors="replace"), end="", flush=True)
            failed |= code != 0
    print(f"Independent suites: {monotonic() - started:.2f}s total", flush=True)
    return int(failed)


if __name__ == "__main__":
    raise SystemExit(run_suites())
