"""Unexecuted and incompletely cleaned commands retain raw invalid evidence without timing acceptance."""

import os
from pathlib import Path
import signal
import subprocess
import sys
from time import monotonic, monotonic_ns, sleep

import pytest

from tests.bundle_measurement_fixture import launcher
from tools.bundle_measurement_identity import file_sha256
from tools.bundle_measurement_process import invoke

OBSERVER = Path(__file__).resolve().parents[1] / "tools/bundle_measurement_child.py"


@pytest.mark.parametrize("missing_python", [False, True])
def test_before_launch_deadline_or_missing_executable(launcher: Path, tmp_path: Path, missing_python: bool) -> None:
    """A past deadline or missing executable preserves empty raw streams and a receipt with no PID."""
    directory = tmp_path / "failed"
    directory.mkdir()
    result = invoke(python=tmp_path / "missing-python" if missing_python else Path(sys.executable),
        observer=OBSERVER, launcher=launcher, arguments=(), directory=directory, environment={},
        deadline_ns=monotonic_ns() + (10_000_000_000 if missing_python else -1),
        required_stage="cli:verify", launcher_sha256=file_sha256(launcher), observer_sha256=file_sha256(OBSERVER), sources={})
    assert result.pid is None and result.returncode is None and result.status is None
    assert ("process launch failed" if missing_python else "path deadline expired") in result.invalid_conditions
    assert result.timed_out != missing_python
    assert Path(result.stdout).read_bytes() == Path(result.stderr).read_bytes() == b""
    assert (directory / "invocation.json").is_file()


def test_escaped_descendant_open_pipes_are_bounded_and_retained(
        launcher: Path, tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    """An unobserved new-session descendant invalidates bounded cleanup; the test then stops that fixture."""
    import tools.bundle_measurement_process as recorder
    monkeypatch.setattr(recorder, "CLEANUP_OUTPUT_TIMEOUT_SECONDS", 0.05)
    pid_file = tmp_path / "escaped.pid"
    ready_file = tmp_path / "escaped.ready"
    child_code = ("import os,time\npid=os.fork()\nif pid==0:\n os.setsid()\n"
                  " print('partial raw output',flush=True)\n"
                  f" open({str(ready_file)!r},'w').write('ready')\n time.sleep(60)\nelse:\n"
                  f" open({str(pid_file)!r},'w').write(str(pid))\n time.sleep(60)\n")
    module = launcher.parents[1] / "migration_check/cli.py"
    replacement = (f"import subprocess,time\n        subprocess.Popen([sys.executable,'-c',{child_code!r}], "
                   "start_new_session=True)\n        time.sleep(60)\n        count = verify(arguments)")
    module.write_text(module.read_text().replace("count = verify(arguments)", replacement))
    directory = tmp_path / "open-pipes"
    directory.mkdir()
    actual_communicate = subprocess.Popen.communicate
    expired = False

    def expire_after_readiness(process: subprocess.Popen[bytes], input: bytes | None = None,
                               timeout: float | None = None) -> tuple[bytes, bytes]:
        """Wait for the actual escaped fixture, then inject timeout without a scheduling race."""
        nonlocal expired
        if not expired:
            limit = monotonic() + 10
            while not (ready_file.exists() and pid_file.exists() and pid_file.read_text().strip()) and monotonic() < limit:
                sleep(0.005)
            expired = True
            raise subprocess.TimeoutExpired(process.args, timeout or 0)
        return actual_communicate(process, input, timeout=timeout)

    monkeypatch.setattr(subprocess.Popen, "communicate", expire_after_readiness)
    try:
        result = invoke(python=Path(sys.executable), observer=OBSERVER, launcher=launcher, arguments=(),
            directory=directory, environment={}, deadline_ns=monotonic_ns() + 20_000_000_000,
            required_stage="cli:verify", launcher_sha256=file_sha256(launcher), observer_sha256=file_sha256(OBSERVER), sources={})
        assert result.timed_out
        assert "output pipes remain open after bounded process cleanup" in result.invalid_conditions
        assert b"partial raw output" in Path(result.stdout).read_bytes()
        assert (directory / "invocation.json").is_file()
    finally:
        if pid_file.exists():
            try:
                os.kill(int(pid_file.read_text()), signal.SIGKILL)
            except ProcessLookupError:
                pass
