"""CI garbage collection registers every root before it removes anything from the store."""

import json
from pathlib import Path
import subprocess
from unittest.mock import patch

import pytest

from tools import ci_store_gc
from tools.ci_store_gc import flake_input_paths, root_commands

pytestmark = [pytest.mark.unit, pytest.mark.environment]


def test_roots_cover_every_target_and_the_development_shell() -> None:
    """`tools.ci_store_gc.root_commands` roots what the next run needs: the test targets,
    both runtimes, the core and base API references and the shell."""
    instantiate, shell = root_commands(Path("roots"))
    assert instantiate[:2] == ["nix-instantiate", "build-support/default.nix"]
    assert [instantiate[index + 1] for index, value in enumerate(instantiate) if value == "-A"] == \
        ["tests", "runtime", "conformance", "apiReferenceCore", "apiReferenceBase"]
    assert "--indirect" in instantiate and "roots/derivation" in instantiate
    assert shell[-4:] == ["--profile", "roots/dev-shell", "--command", "true"]
    assert "path:./nix" in shell


def test_flake_input_paths_include_nested_inputs() -> None:
    """The pinned nixpkgs source is an input of the flake and must stay in the store."""
    archive = {"path": "/nix/store/a-source",
               "inputs": {"nixpkgs": {"path": "/nix/store/b-source", "inputs": {}}}}
    assert sorted(flake_input_paths(json.dumps(archive))) == ["/nix/store/a-source", "/nix/store/b-source"]


def test_garbage_collection_runs_last_and_only_after_all_roots(tmp_path: Path,
                                                               capsys: pytest.CaptureFixture[str]) -> None:
    """A failed root command stops the tool before `nix-store --gc` can run."""
    calls: list[list[str]] = []

    def fake_run(command: list[str], **options: object) -> subprocess.CompletedProcess[str]:
        """Record the command; fail the development shell root."""
        calls.append(command)
        if "develop" in command:
            raise subprocess.CalledProcessError(1, command, "", "error: shell unavailable")
        return subprocess.CompletedProcess(command, 0, "{}", "")

    with patch.object(ci_store_gc, "ROOTS", tmp_path / "roots"), \
         patch("tools.ci_store_gc.subprocess.run", side_effect=fake_run), \
         pytest.raises(subprocess.CalledProcessError):
        ci_store_gc.main()
    assert not any(command[:2] == ["nix-store", "--gc"] for command in calls)
    reported = capsys.readouterr().err
    assert "error: shell unavailable" in reported and "No store paths were removed" in reported

    calls.clear()

    def succeed(command: list[str], **options: object) -> subprocess.CompletedProcess[str]:
        """Record the command; answer the flake archive query with one input."""
        calls.append(command)
        return subprocess.CompletedProcess(command, 0, '{"path": "/nix/store/a-source"}', "")

    with patch.object(ci_store_gc, "ROOTS", tmp_path / "roots"), \
         patch("tools.ci_store_gc.subprocess.run", side_effect=succeed):
        ci_store_gc.main()
    assert calls[-1] == ["nix-store", "--gc"]
    assert any("--realise" in command and "/nix/store/a-source" in command for command in calls)


def test_failed_collection_reports_that_it_may_be_incomplete(tmp_path: Path,
                                                             capsys: pytest.CaptureFixture[str]) -> None:
    """A failure of `nix-store --gc` does not claim that the store is unchanged."""
    def fail_collection(command: list[str], **options: object) -> subprocess.CompletedProcess[str]:
        """Succeed for every root command; fail the collection."""
        if command[:2] == ["nix-store", "--gc"]:
            raise subprocess.CalledProcessError(1, command, "", "error: deletion interrupted")
        return subprocess.CompletedProcess(command, 0, "{}", "")

    with patch.object(ci_store_gc, "ROOTS", tmp_path / "roots"), \
         patch("tools.ci_store_gc.subprocess.run", side_effect=fail_collection), \
         pytest.raises(subprocess.CalledProcessError):
        ci_store_gc.main()
    reported = capsys.readouterr().err
    assert "stopped early" in reported and "No store paths were removed" not in reported
    assert "error: deletion interrupted" in reported and "run the workflow again" in reported


def test_timed_out_command_reports_its_diagnostic(tmp_path: Path, capsys: pytest.CaptureFixture[str]) -> None:
    """A hung Nix command fails with its name, its output and the next action."""
    def time_out(command: list[str], **options: object) -> subprocess.CompletedProcess[str]:
        """Exceed the limit while registering the first root."""
        raise subprocess.TimeoutExpired(command, 600, stderr=b"evaluating derivations")

    with patch.object(ci_store_gc, "ROOTS", tmp_path / "roots"), \
         patch("tools.ci_store_gc.subprocess.run", side_effect=time_out), \
         pytest.raises(subprocess.TimeoutExpired):
        ci_store_gc.main()
    reported = capsys.readouterr().err
    assert "exceeded 600 seconds" in reported and "evaluating derivations" in reported
    assert "No store paths were removed" in reported
