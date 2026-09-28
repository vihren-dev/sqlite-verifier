"""Bound trusted Lean processes; OS isolation is the caller's responsibility."""

from collections.abc import Mapping, Sequence
import os
from pathlib import Path
import resource
import signal
import subprocess
from tempfile import TemporaryFile


def limit_output_files() -> None:
    """Bound each produced file, including captured output streams."""
    resource.setrlimit(resource.RLIMIT_FSIZE, (16 * 1024 * 1024, 16 * 1024 * 1024))


def run_process(
    arguments: Sequence[str], *, write_root: Path,
    environment: Mapping[str, str], timeout: float = 30,
) -> subprocess.CompletedProcess[str]:
    """Run trusted source code with explicit environment, deadline and bounded output."""
    if timeout <= 0:
        raise ValueError("A positive process timeout is required")
    if set(environment) - {"LEAN_PATH", "LEAN_SYSROOT"}:
        raise ValueError("Only trusted Lean search-path settings may enter the process")
    command = list(arguments)
    env = {"HOME": str(write_root), "TMPDIR": str(write_root), "LANG": "C.UTF-8"}
    env.update(environment)
    with TemporaryFile(dir=write_root) as stdout_file, TemporaryFile(dir=write_root) as stderr_file:
        with subprocess.Popen(
            command, cwd=write_root, env=env, stdin=subprocess.DEVNULL,
            stdout=stdout_file, stderr=stderr_file, start_new_session=True,
            preexec_fn=limit_output_files,
        ) as process:
            try:
                process.wait(timeout=timeout)
            except subprocess.TimeoutExpired:
                try:
                    os.killpg(process.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                process.wait()
                raise
            stdout_file.seek(0)
            stderr_file.seek(0)
            stdout = stdout_file.read(1024 * 1024).decode("utf-8", errors="replace")
            stderr = stderr_file.read(1024 * 1024).decode("utf-8", errors="replace")
            return subprocess.CompletedProcess(command, process.returncode, stdout, stderr)
