"""Bound test and CI commands and retain diagnostics without altering production isolation."""

from collections.abc import Mapping, Sequence
from dataclasses import asdict, dataclass
import json
import os
from pathlib import Path
import signal
import shutil
import stat
import subprocess
from time import monotonic


def copy_mutable_tree(source: Path, destination: Path) -> Path:
    """Copy immutable build inputs into a private writable tree while retaining executable bits."""
    shutil.copytree(source, destination)
    for path in [destination, *destination.rglob("*")]:
        owner = stat.S_IRUSR | stat.S_IWUSR | (stat.S_IXUSR if path.is_dir() else 0)
        path.chmod(path.stat().st_mode | owner)
    return destination


@dataclass(frozen=True)
class CommandResult:
    """A complete command observation suitable for assertions and failure messages."""

    command: tuple[str, ...]
    returncode: int
    stdout: str
    stderr: str
    elapsed: float
    timed_out: bool = False

    def diagnostic(self) -> str:
        """Keep malformed output as useful as a normal assertion failure."""
        return json.dumps(asdict(self), indent=2, ensure_ascii=False)

    def json_object(self) -> dict[str, object]:
        """Decode an object or fail with both original streams and command context."""
        try:
            value = json.loads(self.stdout)
        except ValueError as error:
            raise AssertionError(f"Invalid command JSON: {self.diagnostic()}") from error
        if not isinstance(value, dict):
            raise AssertionError(f"Expected JSON object: {self.diagnostic()}")
        return value


class CommandTimeout(AssertionError):
    """Expose the partial observation of a command killed at its deadline."""

    def __init__(self, result: CommandResult) -> None:
        """Retain the observation for callers as well as readable failures."""
        self.result = result
        super().__init__(f"Command timed out: {result.diagnostic()}")


def run_command(arguments: Sequence[str], *, cwd: Path, timeout: float,
                environment: Mapping[str, str] | None = None,
                artifacts: Path | None = None) -> CommandResult:
    """Capture a bounded command; on timeout kill its process group and keep partial output.

    Descendants that start their own session leave the group and are not killed;
    tests run trusted commands, so this is a deadline, not a containment boundary.
    """
    if timeout <= 0 or not arguments:
        raise ValueError("A command and a positive timeout are required")
    command = tuple(map(str, arguments))
    started = monotonic()
    timed_out = False
    with subprocess.Popen(command, cwd=cwd, env=environment, stdin=subprocess.DEVNULL,
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
                          errors="replace", start_new_session=True) as process:
        try:
            stdout, stderr = process.communicate(timeout=timeout)
        except subprocess.TimeoutExpired:
            timed_out = True
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            try:
                stdout, stderr = process.communicate(timeout=5)
            except subprocess.TimeoutExpired:
                stdout, stderr = "", "A descendant outside the process group kept the output pipes open"
    result = CommandResult(command, process.returncode, stdout, stderr,
                           monotonic() - started, timed_out)
    if artifacts is not None:
        artifacts.mkdir(parents=True, exist_ok=True)
        output = artifacts / f"command-{len(list(artifacts.glob('command-*.json'))):04d}.json"
        output.write_text(result.diagnostic() + "\n", encoding="utf-8")
    if timed_out:
        raise CommandTimeout(result)
    return result
