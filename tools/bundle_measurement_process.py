"""Retain complete bounded fresh-process observations without converting failures into timing evidence."""

from collections.abc import Mapping, Sequence
from dataclasses import asdict, dataclass
import json
import os
from pathlib import Path
import signal
import subprocess
from time import monotonic_ns

from tools.bundle_measurement_identity import file_sha256
from tools.bundle_measurement_child import process_journal_path

CLEANUP_OUTPUT_TIMEOUT_SECONDS = 5
"""Bound partial-output collection after recorded groups stop; pipes still open invalidate the observation."""


@dataclass(frozen=True)
class Invocation:
    """Whole external wall time remains authoritative; nested stage spans belong to this same process."""

    command: tuple[str, ...]
    pid: int | None
    started_ns: int
    ended_ns: int
    returncode: int | None
    status: str | None
    timed_out: bool
    error: str | None
    stdout: str
    stderr: str
    stdout_sha256: str
    stderr_sha256: str
    trace: str
    trace_sha256: str | None
    invalid_conditions: tuple[str, ...]

    def wall_ns(self) -> int:
        """Return the externally measured process duration, including startup and observation overhead."""
        return self.ended_ns - self.started_ns


def terminate_observed_groups(pid: int, journal: Path) -> list[str]:
    """Stop the observer first, then its recorded new-session groups; never signal inherited ambient groups."""
    try:
        os.killpg(pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
    conditions: list[str] = []
    if journal.exists():
        for line in journal.read_text().splitlines():
            try:
                record = json.loads(line)
                if not isinstance(record, dict):
                    raise ValueError("process record is not an object")
            except ValueError:
                conditions.append("process journal is malformed; cleanup cannot identify every child")
                continue
            child, group = record.get("pid"), record.get("process_group")
            if type(child) is int and group == child and child > 1:
                try:
                    if os.getpgid(child) == group:
                        os.killpg(group, signal.SIGKILL)
                except ProcessLookupError:
                    pass
    return conditions


def validate_trace(path: Path, *, pid: int | None, started: int, ended: int,
                   launcher_sha256: str, observer_sha256: str,
                   sources: Mapping[str, str], required_stage: str) -> list[str]:
    """Reject missing, changed or other-invocation stage evidence instead of substituting estimated spans."""
    if not path.exists():
        return ["same-invocation stage trace is missing"]
    try:
        trace = json.loads(path.read_text())
        if not isinstance(trace, dict) or any(type(trace[key]) is not int
                for key in ("pid", "active_stages", "started_ns", "ended_ns")):
            return ["stage trace process or timestamps are malformed"]
        if (trace["pid"] != pid or trace["active_stages"] != 0 or trace["isolated_python"] is not True
                or trace["launcher_sha256_before"] != launcher_sha256
                or trace["launcher_sha256_after"] != launcher_sha256
                or trace["observer_sha256"] != observer_sha256
                or not started <= trace["started_ns"] <= trace["ended_ns"] <= ended):
            return ["stage trace process, interval or code identity differs"]
        spans = trace["spans"]
        if not isinstance(spans, list) or not any(span["stage"] == required_stage for span in spans):
            return [f"stage trace has no current {required_stage} caller"]
        parents: dict[int, tuple[int, int]] = {}
        for span in spans:
            if any(type(span[key]) is not int for key in ("identifier", "pid", "started_ns", "ended_ns")):
                return ["stage span identifiers or timestamps are malformed"]
            identifier, parent = span["identifier"], span["parent_identifier"]
            if identifier != len(parents) or (parent is not None and (type(parent) is not int or parent not in parents)):
                return ["stage span order or parent identity differs"]
            if (span["pid"] != pid or sources.get(span["source"]) != span["source_sha256"]
                    or not trace["started_ns"] <= span["started_ns"] <= span["ended_ns"] <= trace["ended_ns"]):
                return ["stage span source, process or interval differs"]
            if parent is not None and not parents[parent][0] <= span["started_ns"] <= span["ended_ns"] <= parents[parent][1]:
                return ["stage span is outside its recorded parent"]
            parents[identifier] = (span["started_ns"], span["ended_ns"])
        return []
    except (ValueError, TypeError, KeyError):
        return ["same-invocation stage trace is malformed"]


def invoke(*, python: Path, observer: Path, launcher: Path, arguments: Sequence[str],
           directory: Path, environment: Mapping[str, str], deadline_ns: int,
           launcher_sha256: str, observer_sha256: str, sources: Mapping[str, str],
           required_stage: str) -> Invocation:
    """Execute one isolated installed launcher and retain exact output bytes even after a timeout."""
    trace = directory / "stages.json"
    stdout_path, stderr_path = directory / "stdout.bin", directory / "stderr.bin"
    command = (str(python), "-I", "-B", str(observer), "--launcher", str(launcher),
               "--trace", str(trace), "--", *arguments)
    process: subprocess.Popen[bytes] | None = None
    timed_out, error = False, None
    cleanup_conditions: list[str] = []
    stdout, stderr = b"", b""
    started = monotonic_ns()
    try:
        remaining = (deadline_ns - started) / 1_000_000_000
        if remaining <= 0:
            raise subprocess.TimeoutExpired(command, 0)
        process = subprocess.Popen(command, cwd=directory, env=environment, stdin=subprocess.DEVNULL,
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE, start_new_session=True)
        remaining = (deadline_ns - monotonic_ns()) / 1_000_000_000
        if remaining <= 0:
            raise subprocess.TimeoutExpired(command, 0)
        stdout, stderr = process.communicate(timeout=remaining)
    except subprocess.TimeoutExpired as failure:
        timed_out = True
        stdout, stderr = failure.output or b"", failure.stderr or b""
        if process is not None:
            cleanup_conditions = terminate_observed_groups(process.pid, process_journal_path(trace))
            try:
                stdout, stderr = process.communicate(timeout=CLEANUP_OUTPUT_TIMEOUT_SECONDS)
            except subprocess.TimeoutExpired as incomplete:
                stdout, stderr = incomplete.output or stdout, incomplete.stderr or stderr
                cleanup_conditions.append("output pipes remain open after bounded process cleanup")
    except OSError as failure:
        error = str(failure)
    finally:
        ended = monotonic_ns()
        if process is not None:
            for stream in (process.stdout, process.stderr):
                if stream is not None:
                    stream.close()
    stdout_path.write_bytes(stdout)
    stderr_path.write_bytes(stderr)
    status = None
    conditions = ["path deadline expired"] if timed_out else ["process launch failed"] if error else []
    conditions.extend(cleanup_conditions)
    try:
        report = json.loads(stdout_path.read_bytes().decode("utf-8"))
        if not isinstance(report, dict) or not isinstance(report.get("status"), str):
            raise ValueError("CLI report has no status")
        status = report["status"]
    except (ValueError, UnicodeError):
        conditions.append("CLI report is malformed; raw stdout retained")
    pid = process.pid if process is not None else None
    conditions.extend(validate_trace(trace, pid=pid, started=started, ended=ended,
        launcher_sha256=launcher_sha256, observer_sha256=observer_sha256,
        sources=sources, required_stage=required_stage))
    receipt = Invocation(command, pid, started, ended, process.returncode if process else None, status,
        timed_out, error, str(stdout_path), str(stderr_path), file_sha256(stdout_path), file_sha256(stderr_path),
        str(trace), file_sha256(trace) if trace.exists() else None, tuple(conditions))
    (directory / "invocation.json").write_text(json.dumps(asdict(receipt), indent=2) + "\n")
    return receipt
