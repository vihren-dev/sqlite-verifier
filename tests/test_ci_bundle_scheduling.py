"""A failed isolated bundle gate retains diagnostics and stops the complete native recipe."""

import json
from pathlib import Path
import subprocess
import sys
from unittest.mock import patch

import pytest

from tools.ci_checks import run_checks
from tests.runtime_support import CommandResult, CommandTimeout, run_command

pytestmark = [pytest.mark.unit, pytest.mark.environment]


@pytest.mark.parametrize("scope", ["test", "package"])
@pytest.mark.parametrize("timed_out", [False, True])
def test_bundle_failure_stops_complete_recipe_and_retains_artifacts(
        tmp_path: Path, scope: str, timed_out: bool, capsys: pytest.CaptureFixture[str]) -> None:
    """Use the real short command harness to retain failure streams before later gates can start."""
    commands: list[list[str]] = []
    limits: list[float] = []
    runtime = tmp_path / "runtime"

    def invoke(command: list[str], *, cwd: Path, environment: dict[str, str], timeout: float,
               artifacts: Path) -> CommandResult:
        """Replace only external build/version work; exercise real stream and artifact retention."""
        commands.append(command)
        if "tests.bundle" not in command:
            return CommandResult(tuple(command), 0, str(runtime) if command[0] == "nix-build" else "", "", 0.01)
        limits.append(timeout)
        assert artifacts == tmp_path / "build/ci-phases/bundle"
        if timed_out:
            script = "import time; print('bundle timeout stdout', flush=True); time.sleep(10)"
            return run_command([sys.executable, "-u", "-c", script], cwd=cwd, timeout=1,
                               environment=environment, artifacts=artifacts)
        script = "import sys; print('bundle failure stdout'); print('bundle failure stderr', file=sys.stderr); sys.exit(7)"
        return run_command([sys.executable, "-c", script], cwd=cwd, timeout=5,
                           environment=environment, artifacts=artifacts)

    with patch("tools.ci_checks.check_resources"), patch("tools.ci_checks.run_command", side_effect=invoke), \
         patch.dict("os.environ", {"SQLITE_VERIFIER_SYSTEM": "aarch64-darwin"}):
        with pytest.raises(CommandTimeout if timed_out else subprocess.CalledProcessError):
            run_checks(scope, "build", "aarch64-darwin", tmp_path)
    assert limits == [900]
    assert "tests.bundle" in commands[-1]
    assert not any(command[0] == "just" for command in commands)
    phase = json.loads((tmp_path / "build/ci-phases.json").read_text())[-1]
    artifact = json.loads((tmp_path / "build/ci-phases/bundle/command-0000.json").read_text())
    assert phase["phase"] == "bundle" and phase["command"] == commands[-1]
    assert phase["exit_code"] == artifact["returncode"] == (-9 if timed_out else 7)
    assert artifact["timed_out"] is timed_out
    assert "bundle " in artifact["stdout"]
    captured = capsys.readouterr()
    if timed_out:
        assert "bundle timeout stdout" in captured.err
    else:
        assert "bundle failure stdout" in captured.out and "bundle failure stderr" in captured.err
