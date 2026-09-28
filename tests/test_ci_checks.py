"""CI reuses only declared artifacts and always invokes the full fresh host recipe."""

import json
from pathlib import Path
import subprocess
from unittest.mock import patch

import pytest

from tools.ci_checks import run_checks
from tests.runtime_support import CommandResult, CommandTimeout

pytestmark = [pytest.mark.unit, pytest.mark.environment]


@pytest.mark.parametrize("mode", ["source", "build"])
@pytest.mark.parametrize("system", ["aarch64-darwin", "x86_64-linux"])
def test_ci_modes_retain_fresh_checks(tmp_path: Path, mode: str, system: str) -> None:
    """Both modes keep host checks; only declared Nix mode supplies artifacts and cached unit receipts."""
    runtime, units = tmp_path / "runtime", tmp_path / "units"
    (runtime / "build").mkdir(parents=True)
    units.mkdir()
    (units / "unit-cases.json").write_text("[]")
    for name in ("native-dependencies.txt", "nix-runtime-roots"):
        (runtime / "build" / name).write_text("loader metadata")
        (tmp_path / "build").mkdir(exist_ok=True)
        destination = tmp_path / "build" / name
        destination.write_text("stale loader metadata")
        destination.chmod(0o444)
    original_bin = tmp_path / "original-bin"
    original_bin.mkdir()
    (runtime / "lean/bin").mkdir(parents=True)
    for compiler in (original_bin / "clang", runtime / "lean/bin/clang"):
        compiler.write_text("#!/bin/sh\nexit 0\n")
        compiler.chmod(0o755)
    commands: list[list[str]] = []
    environments: list[dict[str, str]] = []

    def run(command: list[str], **options: object) -> CommandResult:
        """Return tiny artifact paths without invoking Nix, compilers or a sandbox."""
        commands.append(command)
        environments.append(dict(options["environment"]))
        stdout = str(runtime if "runtime" in command else units) if command[0] == "nix-build" else ""
        return CommandResult(tuple(command), 0, stdout, "", 0.01)

    with patch("tools.ci_checks.check_resources"), patch("tools.ci_checks.run_command", side_effect=run), \
         patch("tools.ci_checks.os.readlink", return_value="net:[before]"), \
         patch.dict("os.environ", {"SQLITE_VERIFIER_SYSTEM": system, "PATH": str(original_bin), "CC": "clang"}, clear=True):
        run_checks("package", mode, system, tmp_path)
    assert commands[-1] == ["just", "package"]
    if mode == "build":
        assert [command[3] for command in commands[:2]] == ["runtime", "unitChecks"]
        assert environments[-1]["SQLITE_VERIFIER_RUNTIME_ROOT"] == str(runtime)
        assert environments[-1]["SQLITE_VERIFIER_UNIT_CHECKS"] == str(units)
        assert environments[-1]["CC"] == "clang"
        assert environments[-1]["PATH"] == str(original_bin)
        assert [str(runtime / "lean/bin/lean"), "--version"] in commands
        assert [str(runtime / "lean/bin/lake"), "--version"] in commands
        assert not (tmp_path / "build/cached-unit").exists()
        assert (tmp_path / "build/native-dependencies.txt").read_text() == "loader metadata"
    else:
        assert commands[0] == ["just", "setup"]
        assert "SQLITE_VERIFIER_UNIT_CHECKS" not in environments[-1]
    probes = [command for command in commands if command[0] == "bwrap"]
    assert bool(probes) == (system == "x86_64-linux")
    if probes:
        assert "--unshare-net" in probes[0] and "--ro-bind" in probes[0]
    assert all(row["exit_code"] == 0 for row in json.loads((tmp_path / "build/ci-phases.json").read_text()))


def test_ci_failure_retains_phase_status(tmp_path: Path) -> None:
    """A failed host recipe fails the job and still records its duration and status."""
    with patch("tools.ci_checks.check_resources"), \
         patch.dict("os.environ", {"SQLITE_VERIFIER_SYSTEM": "aarch64-darwin"}), \
         patch("tools.ci_checks.run_command", return_value=CommandResult((), 7, "failure stdout", "failure stderr", 0.01)):
        with pytest.raises(subprocess.CalledProcessError):
            run_checks("check", "source", "aarch64-darwin", tmp_path)
    assert json.loads((tmp_path / "build/ci-phases.json").read_text())[0]["exit_code"] == 7


def test_ci_timeout_retains_group_runner_diagnostics(tmp_path: Path) -> None:
    """CI delegates timeout cleanup to the shared tested process-group runner and keeps its result."""
    failure = CommandResult(("just", "setup"), -9, "child output", "", 0.01, True)
    with patch("tools.ci_checks.check_resources"), \
         patch.dict("os.environ", {"SQLITE_VERIFIER_SYSTEM": "aarch64-darwin"}), \
         patch("tools.ci_checks.run_command", side_effect=CommandTimeout(failure)) as run:
        with pytest.raises(CommandTimeout):
            run_checks("check", "source", "aarch64-darwin", tmp_path)
    assert run.call_args.kwargs["timeout"] == 330
    assert run.call_args.kwargs["artifacts"] == tmp_path / "build/ci-phases/setup"
    assert json.loads((tmp_path / "build/ci-phases.json").read_text())[0]["exit_code"] == -9
