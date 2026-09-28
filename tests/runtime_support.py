"""Bound test commands and retain diagnostics without altering production isolation."""

from collections.abc import Mapping, Sequence
from dataclasses import asdict, dataclass
import json
import os
from pathlib import Path
import signal
import shutil
import stat
import subprocess
from time import monotonic, sleep


def copy_mutable_tree(source: Path, destination: Path) -> Path:
    """Copy immutable build inputs into a private writable tree while retaining executable bits."""
    shutil.copytree(source, destination)
    for path in [destination, *destination.rglob("*")]:
        owner = stat.S_IRUSR | stat.S_IWUSR | (stat.S_IXUSR if path.is_dir() else 0)
        path.chmod(path.stat().st_mode | owner)
    return destination


@dataclass(frozen=True)
class CommandResult:
    """A complete command observation suitable for assertions and failure artifacts."""

    command: tuple[str, ...]
    returncode: int
    stdout: str
    stderr: str
    elapsed: float
    timed_out: bool = False
    cleanup_error: str | None = None

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
    """Expose timeout diagnostics, including any failure to terminate owned descendants."""

    def __init__(self, result: CommandResult) -> None:
        """Retain the observation for machine reports as well as readable failures."""
        self.result = result
        super().__init__(f"Command timed out: {result.diagnostic()}")


def process_table() -> dict[int, tuple[int, int, str]]:
    """Read POSIX parent/group identities without relying on names or Linux-only /proc."""
    result = subprocess.run(["/bin/ps", "-axo", "pid=,ppid=,pgid=,stat="],
                            text=True, capture_output=True, check=True, timeout=1)
    return {int(pid): (int(parent), int(group), state)
            for pid, parent, group, state in (line.split() for line in result.stdout.splitlines())}


def terminate_tree(pid: int) -> str | None:
    """Kill the connected descendant tree/original group; only the caller can reap its direct child.

    Earlier daemonized, reparented sessions have no attributable POSIX ancestry.
    This test cleanup does not replace the production sandbox's containment.
    """
    owned, groups = {pid}, {pid}
    deadline = monotonic() + 5

    def send(identifier: int, action: int, *, group: bool = False) -> None:
        """Already exited processes need no signal; other errors must remain visible."""
        try:
            (os.killpg if group else os.kill)(identifier, action)
        except ProcessLookupError:
            pass

    try:
        try:
            # Include original-group children even if their leader exited while pipes stayed open.
            send(pid, signal.SIGSTOP, group=True)
            while True:
                if monotonic() >= deadline:
                    raise TimeoutError("process discovery exceeded five seconds")
                table = process_table()
                found = {child for child, (parent, group, _) in table.items()
                         if parent in owned or group in groups}
                new = found - owned
                owned.update(new)
                groups.update(table[child][1] for child in found)
                for child in new:
                    send(child, signal.SIGSTOP)
                # Re-scan after every stop: a discovered child may have forked before it stopped.
                stopped = all(state.startswith(("T", "Z", "X"))
                              for child, (_, group, state) in table.items()
                              if child in owned or group in groups)
                if not new and stopped:
                    break
                sleep(0.02)
        finally:
            # Discovery failure must never leave a process we stopped suspended.
            failure = None
            for identifier, group in [*((value, True) for value in groups),
                                      *((value, False) for value in owned)]:
                try:
                    send(identifier, signal.SIGKILL, group=group)
                except OSError as error:
                    failure = error  # Finish signaling the other owned processes before reporting it.
            if failure is not None:
                raise failure
        while True:
            table = process_table()
            alive = {child for child, (_, group, state) in table.items()
                     if (child in owned or group in groups) and not state.startswith("Z")}
            if not alive:
                return None
            if monotonic() >= deadline:
                raise TimeoutError(f"descendants did not terminate: {sorted(alive)}")
            sleep(0.02)
    except (OSError, subprocess.SubprocessError, ValueError, TimeoutError) as error:
        return f"{type(error).__name__}: {error}"


def run_command(arguments: Sequence[str], *, cwd: Path, timeout: float,
                environment: Mapping[str, str] | None = None,
                artifacts: Path | None = None) -> CommandResult:
    """Capture bounded commands; on timeout kill descendants, reap the leader and retain diagnostics."""
    if timeout <= 0 or not arguments:
        raise ValueError("A command and a positive timeout are required")
    command = tuple(map(str, arguments))
    started = monotonic()
    timed_out = False
    cleanup_error = None
    process = subprocess.Popen(command, cwd=cwd, env=environment, stdin=subprocess.DEVNULL,
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
                               errors="replace", start_new_session=True)
    try:
        try:
            stdout, stderr = process.communicate(timeout=timeout)
        except subprocess.TimeoutExpired:
            timed_out = True
            cleanup_error = terminate_tree(process.pid)
            process.kill()
            try:
                stdout, stderr = process.communicate(timeout=2)
            except subprocess.TimeoutExpired as error:
                cleanup_error = (cleanup_error or "") + "; timed out draining descendant pipes"
                stdout = (error.output or b"").decode("utf-8", errors="replace")
                stderr = (error.stderr or b"").decode("utf-8", errors="replace")
                process.wait(timeout=2)
    finally:
        # Do not let Popen.__exit__ wait without a deadline after a failed cleanup.
        if process.stdout is not None:
            process.stdout.close()
        if process.stderr is not None:
            process.stderr.close()
    result = CommandResult(command, process.returncode, stdout, stderr,
                           monotonic() - started, timed_out, cleanup_error)
    if artifacts is not None:
        artifacts.mkdir(parents=True, exist_ok=True)
        # Each fixture supplies a private directory; command order is useful in diagnostics.
        output = artifacts / f"command-{len(list(artifacts.glob('command-*.json'))):04d}.json"
        output.write_text(result.diagnostic() + "\n", encoding="utf-8")
    if timed_out:
        raise CommandTimeout(result)
    return result
