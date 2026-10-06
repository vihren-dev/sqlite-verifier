"""Fresh child receipts preserve raw failures, bound process groups and validate same-invocation spans."""

from collections.abc import Sequence
import json
import os
from pathlib import Path
import signal
import sys
from time import monotonic_ns

import pytest

from tests.bundle_measurement_fixture import launcher
from tools.bundle_measurement_identity import file_sha256
from tools.bundle_measurement_process import Invocation, invoke, validate_trace

OBSERVER = Path(__file__).resolve().parents[1] / "tools/bundle_measurement_child.py"


def run_observed(launcher: Path, directory: Path, arguments: Sequence[str] = (), timeout: float = 10) -> Invocation:
    """Execute the deterministic installed fixture with the real bounded observer/recorder."""
    directory.mkdir()
    sources = {str(path): file_sha256(path) for path in (launcher.parents[1] / "migration_check").glob("*.py")}
    return invoke(python=Path(sys.executable), observer=OBSERVER, launcher=launcher, arguments=arguments,
                  directory=directory, environment={"HOME": str(directory), "TMPDIR": str(directory)},
                  deadline_ns=monotonic_ns() + int(timeout * 1_000_000_000), required_stage="cli:verify",
                  launcher_sha256=file_sha256(launcher), observer_sha256=file_sha256(OBSERVER), sources=sources)


@pytest.mark.parametrize("arguments,code,status", [((), 0, "VERIFIED"), (("negative",), 1, "VIOLATED")])
def test_real_fresh_receipts_and_unmodified_cli(launcher: Path, tmp_path: Path,
                                              arguments: tuple[str, ...], code: int, status: str) -> None:
    """Both public outcomes retain fresh processes, exact raw streams and externally measured wall intervals."""
    first = run_observed(launcher, tmp_path / "first", arguments)
    second = run_observed(launcher, tmp_path / "second", arguments)
    assert first.pid != second.pid
    for result in (first, second):
        assert (result.returncode, result.status, result.invalid_conditions) == (code, status, ())
        assert result.wall_ns() > 0 and "-I" in result.command and "-B" in result.command
        assert file_sha256(Path(result.stdout)) == result.stdout_sha256
        assert file_sha256(Path(result.stderr)) == result.stderr_sha256
        assert file_sha256(Path(result.trace)) == result.trace_sha256
        report = json.loads(Path(result.stdout).read_bytes())
        assert report["pid"] == result.pid
        assert json.loads((Path(result.stdout).parent / "invocation.json").read_text())["ended_ns"] == result.ended_ns


def test_malformed_utf8_output_is_retained_exactly(launcher: Path, tmp_path: Path) -> None:
    """An invalid report cannot become timing evidence, and its original bytes remain available."""
    module = launcher.parents[1] / "migration_check/cli.py"
    module.write_text(module.read_text().replace("print(json.dumps", "sys.stdout.buffer.write(b'\\xff'); sys.stdout.flush()\n    print(json.dumps"))
    result = run_observed(launcher, tmp_path / "bad-output")
    assert result.status is None and "CLI report is malformed; raw stdout retained" in result.invalid_conditions
    assert Path(result.stdout).read_bytes().startswith(b"\xff")


def test_changed_or_other_process_trace_refused(launcher: Path, tmp_path: Path) -> None:
    """Code hashes and process/timestamp identities bind every span to the measured command."""
    result = run_observed(launcher, tmp_path / "trace")
    trace = Path(result.trace)
    original = json.loads(trace.read_text())
    kwargs = dict(pid=result.pid, started=result.started_ns, ended=result.ended_ns,
                  launcher_sha256=file_sha256(launcher), observer_sha256=file_sha256(OBSERVER),
                  sources={str(path): file_sha256(path) for path in (launcher.parents[1] / "migration_check").glob("*.py")},
                  required_stage="cli:verify")
    for key, value in (("pid", result.pid + 1), ("started_ns", float(original["started_ns"])),
                       ("observer_sha256", "other")):
        trace.write_text(json.dumps({**original, key: value}))
        assert validate_trace(trace, **kwargs)
    trace.write_text(json.dumps(original))
    kwargs["sources"] = {}
    assert validate_trace(trace, **kwargs) == ["stage span source, process or interval differs"]


@pytest.mark.parametrize("malformed_journal", [False, True])
def test_timeout_kills_recorded_separate_group(launcher: Path, tmp_path: Path,
                                             monkeypatch: pytest.MonkeyPatch, malformed_journal: bool) -> None:
    """The timeout retains partial streams and stops an actual new-session descendant of the observer."""
    module = launcher.parents[1] / "migration_check/cli.py"
    append = 'open("stages.processes.jsonl","a").write("{")' if malformed_journal else "pass"
    module.write_text(module.read_text().replace("count = verify(arguments)", """import subprocess,time
        child = subprocess.Popen([sys.executable,"-c","import time; time.sleep(60)"], start_new_session=True)
        APPEND_JOURNAL
        print(child.pid, flush=True)
        time.sleep(60)
        count = verify(arguments)""".replace("APPEND_JOURNAL", append)))
    actual_kill = os.killpg
    signals: list[tuple[int, int]] = []

    def retain_actual_signal(group: int, value: int) -> None:
        """Retain signal delivery to actual spawned groups without relying on orphan-reaping latency."""
        signals.append((group, value))
        actual_kill(group, value)

    monkeypatch.setattr(os, "killpg", retain_actual_signal)
    result = run_observed(launcher, tmp_path / "timeout", timeout=1)
    assert result.timed_out and result.wall_ns() < 6_000_000_000 and "path deadline expired" in result.invalid_conditions
    child = int(Path(result.stdout).read_bytes())
    journal = Path(result.trace).with_suffix(".processes.jsonl")
    spawn = json.loads(journal.read_text().splitlines()[0])
    assert spawn["pid"] == spawn["process_group"] == child
    assert (child, signal.SIGKILL) in signals and (result.pid, signal.SIGKILL) in signals
    condition = "process journal is malformed; cleanup cannot identify every child"
    assert (condition in result.invalid_conditions) == malformed_journal
