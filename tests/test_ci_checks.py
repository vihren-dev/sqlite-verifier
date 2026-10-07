"""CI reuses only declared artifacts and always invokes the full fresh host recipe."""

import json
from pathlib import Path
import re
import shlex
import subprocess
from unittest.mock import patch

import pytest

from tools.ci_checks import NIX_TEST_BUILD_OPTIONS, run_checks
from tests.runtime_support import CommandResult, CommandTimeout

pytestmark = [pytest.mark.unit, pytest.mark.environment]


@pytest.mark.parametrize("scope", ["test", "package"])
@pytest.mark.parametrize("mode", ["source", "build"])
@pytest.mark.parametrize("system", ["aarch64-darwin", "x86_64-linux"])
def test_hosted_job_covers_sequential_phase_budgets(
        tmp_path: Path, scope: str, mode: str, system: str) -> None:
    """A hosted job must allow the actual complete phase limits plus setup and artifact retention."""
    workflow = (Path(__file__).resolve().parents[1] / ".github/workflows/ci.yml").read_text()
    check_job = workflow.split("  check:\n", 1)[1].split("\n  publish:", 1)[0]
    match = re.search(r"(?m)^    timeout-minutes: ([1-9][0-9]*)$", check_job)
    assert match is not None
    budgets: list[float] = []

    def invoke(command: list[str], *, cwd: Path, environment: dict[str, str],
               timeout: float, artifacts: Path) -> CommandResult:
        """Observe real orchestration limits while replacing only external build and version work."""
        budgets.append(timeout)
        output = str(tmp_path / "runtime") if command[0] == "nix-build" else ""
        return CommandResult(tuple(command), 0, output, "", 0.01)

    with patch("tools.ci_checks.check_resources"), patch("tools.ci_checks.run_command", side_effect=invoke), \
         patch.dict("os.environ", {"SQLITE_VERIFIER_SYSTEM": system}):
        run_checks(scope, mode, system, tmp_path)
    assert sum(budgets) + 300 <= int(match.group(1)) * 60, \
        f"Hosted job budget cannot cover {sum(budgets)} seconds of phases plus 300 seconds of setup and artifacts"


@pytest.mark.parametrize("mode", ["source", "build"])
@pytest.mark.parametrize("system", ["aarch64-darwin", "x86_64-linux"])
def test_ci_modes_retain_fresh_checks(tmp_path: Path, mode: str, system: str) -> None:
    """Both modes retain complete host recipes and the selected native system's bundle schedule."""
    runtime = tmp_path / "runtime"
    (runtime / "build").mkdir(parents=True)
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
        stdout = str(runtime) if command[0] == "nix-build" else ""
        return CommandResult(tuple(command), 0, stdout, "", 0.01)

    with patch("tools.ci_checks.check_resources"), patch("tools.ci_checks.run_command", side_effect=run), \
         patch.dict("os.environ", {"SQLITE_VERIFIER_SYSTEM": system, "PATH": str(original_bin), "CC": "clang"}, clear=True):
        run_checks("package", mode, system, tmp_path)
        assert commands[-1] == ["just", "package"]
        if system == "aarch64-darwin":
            assert commands[-2][3] == "tests.bundle"
        run_checks("test", mode, system, tmp_path)
    assert commands[-1] == ["just", "test-full"]
    bundle_commands = [command for command in commands if "tests.bundle" in command]
    if system == "aarch64-darwin":
        assert len(bundle_commands) == 2
        assert commands[-2] == bundle_commands[-1]
        assert bundle_commands[0] == bundle_commands[1] == [
            "nix-build", "build-support/default.nix", "-A", "tests.bundle",
            "--out-link", "build/nix-tests-bundle", *NIX_TEST_BUILD_OPTIONS]
    else:
        assert bundle_commands == []
    if mode == "build":
        assert commands[0][3] == "runtime"
        assert environments[-1]["SQLITE_VERIFIER_RUNTIME_ROOT"] == str(runtime)
        assert "SQLITE_VERIFIER_UNIT_CHECKS" not in environments[-1]
        assert environments[-1]["CC"] == "clang"
        assert environments[-1]["PATH"] == str(original_bin)
        assert [str(runtime / "lean/bin/lean"), "--version"] in commands
        assert [str(runtime / "lean/bin/lake"), "--version"] in commands
        assert not (tmp_path / "build/cached-unit").exists()
    else:
        assert commands[0] == ["just", "setup"]
        assert "SQLITE_VERIFIER_UNIT_CHECKS" not in environments[-1]
    assert all(row["exit_code"] == 0 for row in json.loads((tmp_path / "build/ci-phases.json").read_text()))


def test_bundle_policy_matches_existing_nix_test_recipes() -> None:
    """The isolated phase uses the actual complete recipes' isolation options, so their policies cannot drift."""
    recipes = (Path(__file__).resolve().parents[1] / "justfile").read_text().splitlines()
    targets: set[str] = set()
    for line in recipes:
        if not line.lstrip().startswith("timeout 900 nix-build "):
            continue
        words = shlex.split(line)
        if "--option" not in words:
            continue
        targets.add(words[words.index("-A") + 1])
        assert tuple(words[words.index("--option"):]) == NIX_TEST_BUILD_OPTIONS
    assert targets == {"developmentTests", "tests", "tests.atuin"}


def test_ci_failure_retains_phase_status(tmp_path: Path) -> None:
    """A failed host recipe fails the job and still records its duration and status."""
    with patch("tools.ci_checks.check_resources"), \
         patch.dict("os.environ", {"SQLITE_VERIFIER_SYSTEM": "aarch64-darwin"}), \
         patch("tools.ci_checks.run_command", return_value=CommandResult((), 7, "failure stdout", "failure stderr", 0.01)):
        with pytest.raises(subprocess.CalledProcessError):
            run_checks("test", "source", "aarch64-darwin", tmp_path)
    assert json.loads((tmp_path / "build/ci-phases.json").read_text())[0]["exit_code"] == 7


def test_ci_timeout_retains_group_runner_diagnostics(tmp_path: Path) -> None:
    """CI delegates timeout cleanup to the shared tested process-group runner and keeps its result."""
    failure = CommandResult(("just", "setup"), -9, "child output", "", 0.01, True)
    with patch("tools.ci_checks.check_resources"), \
         patch.dict("os.environ", {"SQLITE_VERIFIER_SYSTEM": "aarch64-darwin"}), \
         patch("tools.ci_checks.run_command", side_effect=CommandTimeout(failure)) as run:
        with pytest.raises(CommandTimeout):
            run_checks("test", "source", "aarch64-darwin", tmp_path)
    assert run.call_args.kwargs["timeout"] == 330
    assert run.call_args.kwargs["artifacts"] == tmp_path / "build/ci-phases/setup"
    assert json.loads((tmp_path / "build/ci-phases.json").read_text())[0]["exit_code"] == -9
