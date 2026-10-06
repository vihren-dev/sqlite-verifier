"""Whole paths retain fresh cold commands, exact identities and a single shared deadline."""

from dataclasses import replace
import gzip
import json
from pathlib import Path

import pytest

from tests.bundle_measurement_fixture import launcher
from tests.bundle_measurement_path_fixture import trial_spec
from tools.bundle_measurement_paths import TrialSpec, execute_path


def test_complete_both_paths_fresh_cold_same_runtime(trial_spec: TrialSpec, tmp_path: Path) -> None:
    """Three real child invocations bind stage spans to complete path walls and retain preparation artifacts."""
    identity = trial_spec.identity()
    old = execute_path(trial_spec, "verify", tmp_path / "verify", identity)
    new = execute_path(trial_spec, "bundle", tmp_path / "bundle", identity)
    assert old.invalid_conditions == new.invalid_conditions == ()
    assert old.filesystem_device == new.filesystem_device
    assert len(old.commands) == 1 and len(new.commands) == 2
    assert len({command.pid for command in (*old.commands, *new.commands)}) == 3
    assert [command.status for command in new.commands] == ["PREPARED", "VERIFIED"]
    for observation in (old, new):
        assert observation.wall_ns() >= sum(command.wall_ns() for command in observation.commands)
        assert observation.started_ns <= observation.commands[0].started_ns
        assert observation.commands[-1].ended_ns <= observation.ended_ns
        assert all(Path(directory).is_dir() for directory in observation.cache_directories)
        with gzip.open(observation.identity_before, "rt") as stream:
            assert json.load(stream) == identity
        with gzip.open(observation.identity_after, "rt") as stream:
            assert json.load(stream) == identity
        with gzip.open(observation.artifacts, "rt") as stream:
            files = json.load(stream)["files"]
        assert "command-0/stages.json" in files and "command-0/stdout.bin" in files
        for index in range(len(observation.commands)):
            with gzip.open(Path(observation.artifacts).parent / f"command-{index}/cache-before.json.gz", "rt") as stream:
                assert json.load(stream)["empty"] == [True, True, True]
    assert (tmp_path / "bundle/proof.ndjson").read_bytes() == b"exact fixture bundle"
    assert not list((tmp_path / "bundle/stage-store").iterdir())
    assert (tmp_path / "bundle/agent/modules/Proofs.olean").is_file()
    assert trial_spec.identity() == identity


def test_changed_input_refuses_execution_and_preserves_manifests(trial_spec: TrialSpec, tmp_path: Path) -> None:
    """A changed source tree has no invented child PID or duration and retains the differing raw identity."""
    identity = trial_spec.identity()
    (trial_spec.runtime / "migration_check/new.py").write_bytes(b"changed source")
    result = execute_path(trial_spec, "verify", tmp_path / "changed", identity)
    assert result.commands == () and result.wall_ns() is None
    assert "identity changed before execution" in result.invalid_conditions[0]
    assert Path(result.identity_before).is_file() and Path(result.identity_after).is_file()


def test_existing_cold_directory_is_not_overwritten(trial_spec: TrialSpec, tmp_path: Path) -> None:
    """An interrupted or populated observation remains intact when the caller attempts its path again."""
    directory = tmp_path / "existing"
    directory.mkdir()
    (directory / "raw.bin").write_bytes(b"preserved")
    with pytest.raises(FileExistsError):
        execute_path(trial_spec, "verify", directory, trial_spec.identity())
    assert (directory / "raw.bin").read_bytes() == b"preserved"


def test_output_cannot_change_selected_source_tree(trial_spec: TrialSpec) -> None:
    """Preflight rejects an evidence directory inside immutable runtime/source identities before creating it."""
    output = trial_spec.runtime / "trial-output"
    with pytest.raises(ValueError, match="inside runtime/source"):
        execute_path(trial_spec, "verify", output, trial_spec.identity())
    assert not output.exists()


def test_changed_source_during_execution_is_invalid_but_retained(trial_spec: TrialSpec, tmp_path: Path) -> None:
    """Source changes cannot be hidden by a successful CLI status or post-execution identity update."""
    module = trial_spec.runtime / "migration_check/cli.py"
    module.write_text(module.read_text().replace("print(json.dumps", f"open({str(module)!r},'a').write('\\n# changed during command\\n')\n    print(json.dumps"))
    baseline = trial_spec.identity()
    result = execute_path(trial_spec, "verify", tmp_path / "mutated", baseline)
    assert result.commands[0].status == "VERIFIED"
    # The file changes after the observed verify stage returns; the post-path manifest still detects it.
    assert result.commands[0].invalid_conditions == ()
    assert "identity changed during execution" in result.invalid_conditions[-1]
    assert Path(result.commands[0].stdout).is_file()


def test_warm_active_checker_cache_refuses_second_command(trial_spec: TrialSpec, tmp_path: Path) -> None:
    """A preparation side effect cannot silently warm the checker cache before its fresh invocation."""
    module = trial_spec.runtime / "migration_check/prepare.py"
    module.write_text(module.read_text().replace("return compile_contract()",
        'import os\n    (Path(os.environ["MIGRATION_CHECK_STAGE_STORE"])/"warm.olean").write_bytes(b"warm")\n    return compile_contract()'))
    result = execute_path(trial_spec, "bundle", tmp_path / "warm", trial_spec.identity())
    assert len(result.commands) == 1 and result.commands[0].status == "PREPARED"
    assert result.invalid_conditions == ("verify-bundle starts with nonempty active caches; invocation refused",)
    assert (tmp_path / "warm/stage-store/warm.olean").read_bytes() == b"warm"


def test_checker_refutation_cannot_be_inferred_from_cli_status(trial_spec: TrialSpec, tmp_path: Path) -> None:
    """The path requires the observed direct checker code as well as the expected public report."""
    process = trial_spec.runtime / "migration_check/process.py"
    process.write_text(process.read_text().replace('CompletedProcess(arguments,0', 'CompletedProcess(arguments,2'))
    result = execute_path(trial_spec, "verify", tmp_path / "wrong-checker", trial_spec.identity())
    assert result.commands[0].status == "VERIFIED" and result.commands[0].returncode == 0
    assert result.invalid_conditions == ("migration-proof-checker result was [2]; expected observed checker code 0",)


def test_combined_path_commands_share_one_deadline(trial_spec: TrialSpec, tmp_path: Path,
                                                 monkeypatch: pytest.MonkeyPatch) -> None:
    """The second command receives the same absolute deadline, rather than a second full timeout budget."""
    import tools.bundle_measurement_paths as paths
    actual_invoke = paths.invoke
    deadlines: list[int] = []

    def retain_deadline(**keywords: object) -> paths.Invocation:
        """Forward actual child execution while retaining its common absolute deadline."""
        deadlines.append(keywords["deadline_ns"])
        return actual_invoke(**keywords)

    monkeypatch.setattr(paths, "invoke", retain_deadline)
    result = execute_path(trial_spec, "bundle", tmp_path / "deadline", trial_spec.identity())
    assert result.invalid_conditions == () and len(deadlines) == 2 and deadlines[0] == deadlines[1]
    assert deadlines[0] == result.started_ns + trial_spec.timeout_ns


@pytest.mark.parametrize("timeout", [0, -1, True, 1.5])
def test_invalid_timeout_is_refused(trial_spec: TrialSpec, timeout: object) -> None:
    """Only exact positive integer-nanosecond budgets can describe a cold comparison."""
    with pytest.raises(ValueError, match="positive integer nanoseconds"):
        replace(trial_spec, timeout_ns=timeout)


@pytest.mark.parametrize("field,value", [("common_arguments", ["mutable"]), ("candidate_arguments", (1,)),
                                         ("input_roots", [Path("mutable")])])
def test_mutable_or_untyped_context_is_refused(trial_spec: TrialSpec, field: str, value: object) -> None:
    """The exact argv/source context cannot mutate between raw pairs without changing the specification."""
    with pytest.raises(ValueError, match="immutable"):
        replace(trial_spec, **{field: value})
