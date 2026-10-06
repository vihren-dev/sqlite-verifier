"""Unexecuted and incompletely cleaned commands retain raw invalid evidence without timing acceptance."""

import os
from pathlib import Path
import signal
import sys
from time import monotonic_ns

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
    child_code = ("import os,time\nif os.fork()==0:\n os.setsid()\n"
                  f" open({str(pid_file)!r},'w').write(str(os.getpid()))\n"
                  " print('partial raw output',flush=True)\n time.sleep(60)\nelse:\n time.sleep(60)\n")
    module = launcher.parents[1] / "migration_check/cli.py"
    replacement = (f"import subprocess,time\n        subprocess.Popen([sys.executable,'-c',{child_code!r}], "
                   "start_new_session=True)\n        time.sleep(60)\n        count = verify(arguments)")
    module.write_text(module.read_text().replace("count = verify(arguments)", replacement))
    directory = tmp_path / "open-pipes"
    directory.mkdir()
    try:
        result = invoke(python=Path(sys.executable), observer=OBSERVER, launcher=launcher, arguments=(),
            directory=directory, environment={}, deadline_ns=monotonic_ns() + 2_000_000_000,
            required_stage="cli:verify", launcher_sha256=file_sha256(launcher), observer_sha256=file_sha256(OBSERVER), sources={})
        assert result.timed_out and result.wall_ns() < 7_000_000_000
        assert "output pipes remain open after bounded process cleanup" in result.invalid_conditions
        assert b"partial raw output" in Path(result.stdout).read_bytes()
        assert (directory / "invocation.json").is_file()
    finally:
        if pid_file.exists():
            try:
                os.killpg(int(pid_file.read_text()), signal.SIGKILL)
            except ProcessLookupError:
                pass
