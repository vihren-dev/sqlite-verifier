"""Exercise outer deadlines across helper sessions and trusted Lean processes."""

import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import textwrap

import pytest

from tests import runtime_support
from tests.runtime_support import CommandTimeout, process_table, run_command

ROOT = Path(__file__).resolve().parents[1]
pytestmark = [pytest.mark.integration, pytest.mark.environment, pytest.mark.requires_native("/bin/ps")]


def terminate_recorded(directory: Path) -> None:
    """A failed regression must clean up its own explicitly recorded children too."""
    for path in directory.glob("*.pid"):
        try:
            os.kill(int(path.read_text()), signal.SIGKILL)
        except ProcessLookupError:
            pass


def assert_terminated(directory: Path, names: set[str]) -> None:
    """Descendants may briefly be init-owned zombies; only the direct leader is waitpid-reapable."""
    assert {path.name for path in directory.glob("*.pid")} == names
    table = process_table()
    for path in directory.glob("*.pid"):
        pid = int(path.read_text())
        assert pid not in table or table[pid][2].startswith("Z"), (path, table.get(pid))


def test_outer_timeout_kills_nested_sessions(tmp_path: Path) -> None:
    """An outer deadline kills an inner helper's new session and a further detached child, preserving siblings."""
    leaf = "import os,time; from pathlib import Path; Path('leaf.pid').write_text(str(os.getpid())); time.sleep(60)"
    middle = ("import os,subprocess,sys; from pathlib import Path; "
              "Path('middle.pid').write_text(str(os.getpid())); "
              f"subprocess.Popen([sys.executable,'-c',{leaf!r}],start_new_session=True).wait()")
    outer = ("import os,sys; from pathlib import Path; "
             f"sys.path.insert(0,{str(ROOT)!r}); from tests.runtime_support import run_command; "
             "Path('outer.pid').write_text(str(os.getpid())); "
             "print('outer stdout',flush=True); print('outer stderr',file=sys.stderr,flush=True); "
             f"run_command([sys.executable,'-c',{middle!r}],cwd=Path.cwd(),timeout=60)")
    sibling = subprocess.Popen([sys.executable, "-c", "import time; time.sleep(60)"], start_new_session=True)
    try:
        with pytest.raises(CommandTimeout) as failure:
            run_command([sys.executable, "-c", outer], cwd=tmp_path, timeout=3, artifacts=tmp_path / "artifacts")
        result = failure.value.result
        assert result.timed_out and result.returncode != 0 and result.cleanup_error is None, result.diagnostic()
        assert "outer stdout" in result.stdout and "outer stderr" in result.stderr
        assert json.loads((tmp_path / "artifacts/command-0000.json").read_text())["timed_out"]
        assert_terminated(tmp_path, {"outer.pid", "middle.pid", "leaf.pid"})
        assert int((tmp_path / "outer.pid").read_text()) not in process_table(), "Direct leader was not reaped"
        assert sibling.poll() is None, "Timeout killed an unrelated sibling"
    finally:
        terminate_recorded(tmp_path)
        sibling.kill()
        sibling.wait(timeout=2)


def test_exited_leader_cannot_leave_original_group_alive(tmp_path: Path) -> None:
    """An exited leader whose original-group child holds captured pipes still receives complete cleanup."""
    leaf = "import os,time; from pathlib import Path; Path('leaf.pid').write_text(str(os.getpid())); time.sleep(60)"
    outer = f"import subprocess,sys; subprocess.Popen([sys.executable,'-c',{leaf!r}])"
    try:
        with pytest.raises(CommandTimeout) as failure:
            run_command([sys.executable, "-c", outer], cwd=tmp_path, timeout=3)
        assert failure.value.result.cleanup_error is None, failure.value.result.diagnostic()
        assert_terminated(tmp_path, {"leaf.pid"})
    finally:
        terminate_recorded(tmp_path)


def test_discovery_failure_bounds_pipe_draining(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    """Failed native discovery is reported and cannot leave stopped owned groups or wait forever on escaped pipes."""
    leaf = "import os,time; from pathlib import Path; Path('leaf.pid').write_text(str(os.getpid())); time.sleep(60)"
    outer = ("import os,subprocess,sys; from pathlib import Path; "
             "Path('outer.pid').write_text(str(os.getpid())); print('partial',flush=True); "
             f"subprocess.Popen([sys.executable,'-c',{leaf!r}],start_new_session=True).wait()")

    def unavailable() -> dict[int, tuple[int, int, str]]:
        """Simulate an unavailable process table after the owned root has been stopped."""
        raise OSError("process discovery unavailable")

    monkeypatch.setattr(runtime_support, "process_table", unavailable)
    try:
        with pytest.raises(CommandTimeout) as failure:
            run_command([sys.executable, "-c", outer], cwd=tmp_path, timeout=3, artifacts=tmp_path / "artifacts")
        result = failure.value.result
        assert result.elapsed < 10 and "partial" in result.stdout, result.diagnostic()
        assert result.cleanup_error is not None
        assert "process discovery unavailable" in result.cleanup_error and "draining" in result.cleanup_error
        record = json.loads((tmp_path / "artifacts/command-0000.json").read_text())
        assert record["cleanup_error"] == result.cleanup_error
        outer_pid = int((tmp_path / "outer.pid").read_text())
        assert outer_pid not in process_table(), "Direct child was not reaped after discovery failure"
    finally:
        terminate_recorded(tmp_path)


def test_outer_timeout_kills_proof_process(tmp_path: Path) -> None:
    """A pytest-level deadline also terminates the actual separately grouped proof process."""
    executable = Path(sys.executable)
    inputs = outputs = tmp_path
    program = inputs / "parent.py"
    program.write_text(textwrap.dedent(f'''\
        import sys
        from pathlib import Path
        sys.path.insert(0, {str(ROOT)!r})
        from migration_check import process as runner
        original = runner.subprocess.Popen
        def launch(*arguments, **keywords):
            process = original(*arguments, **keywords)
            Path({str(outputs / 'proof.pid')!r}).write_text(str(process.pid))
            return process
        runner.subprocess.Popen = launch
        runner.run_process([{str(executable)!r}, '-I', '-c', 'import time; time.sleep(60)'],
            write_root=Path({str(outputs)!r}), environment={{}}, timeout=60)
    '''))
    try:
        with pytest.raises(CommandTimeout) as failure:
            run_command([sys.executable, str(program)], cwd=inputs, timeout=3)
        assert failure.value.result.cleanup_error is None, failure.value.result.diagnostic()
        assert_terminated(outputs, {"proof.pid"})
    finally:
        terminate_recorded(outputs)
