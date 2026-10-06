"""Named configurations and actual campaign files use synthetic paths, never performance trials."""

from dataclasses import replace
import json
from pathlib import Path
import shutil
import sys

import pytest

from migration_check.cli import arguments
from tests.bundle_measurement_campaign_fixture import synthetic_paths
from tools.bundle_measurement import main, named_trial_spec
from tools.bundle_measurement_paths import CHECKER_EXIT_BY_STATUS, CLI_EXIT_BY_STATUS

CASES = [("small-success", "add_column_then_table", "3.51.0", "VERIFIED"),
         ("checked-refutation", "missing_required_column", "3.51.0", "VIOLATED"),
         ("atuin", "atuin", "3.46.0", "VERIFIED")]
"""Independent expected selections for the three documented source examples."""


@pytest.fixture
def named_runtime(tmp_path: Path) -> Path:
    """Copy shipped sources into an explicitly synthetic installation without runnable verification code."""
    runtime = tmp_path / "synthetic runtime % # ü"
    (runtime / "bin").mkdir(parents=True)
    launcher = runtime / "bin/migration-check"
    launcher.write_text("#!/bin/sh\necho 'synthetic configuration fixture; do not execute'\nexit 99\n")
    launcher.chmod(0o755)
    (runtime / "python-path").write_text(str(Path(sys.executable).resolve()) + "\n")
    shutil.copytree(Path(__file__).resolve().parents[1] / "examples", runtime / "examples")
    return runtime


def command(runtime: Path, output: Path, name: str = "small-success") -> list[str]:
    """Provide every required selector and one shared whole-path timeout explicitly."""
    return ["--case", name, "--runtime", str(runtime), "--python", sys.executable,
            "--output", str(output), "--timeout-seconds", "7"]


@pytest.mark.parametrize("name,candidate,profile,status", CASES)
def test_named_roles_match_current_cli(named_runtime: Path, name: str, candidate: str,
                                      profile: str, status: str) -> None:
    """All three public parsers consume the same protected inputs and the correct candidate roles."""
    spec = named_trial_spec(name, runtime=named_runtime, python=Path(sys.executable), timeout_ns=7_000_000_000)
    selected = named_runtime / "examples" / candidate
    approved = selected / "approved" if name == "atuin" else named_runtime / "examples/approved"
    schema = selected / "schema.sql" if name == "atuin" else approved / "schema.sql"
    verify = arguments(("verify", *spec.common_arguments, *spec.candidate_arguments))
    prepared = arguments(("prepare", *spec.common_arguments, *spec.candidate_arguments,
                          "--workspace", "/new/agent", "--output", "/new/proof.ndjson"))
    checked = arguments(("verify-bundle", *spec.common_arguments, "--bundle", "/new/proof.ndjson"))
    for options in (verify, prepared, checked):
        assert options.profile == profile and options.format == "json"
        assert options.schema == schema and options.requirements == approved / "Requirements.lean"
        assert options.interpretation == approved / "Interpretation.lean"
        assert options.migration == selected / "migration.sql"
    assert verify.next_interpretation == prepared.next_interpretation == selected / "NextInterpretation.lean"
    assert verify.proofs == prepared.proofs == selected / "Proofs.lean"
    assert spec.input_roots == ((selected,) if name == "atuin" else (approved, selected))
    assert spec.expected_status == status and spec.timeout_ns == 7_000_000_000
    assert CLI_EXIT_BY_STATUS[spec.expected_status] == (1 if status == "VIOLATED" else 0)
    assert CHECKER_EXIT_BY_STATUS[spec.expected_status] == (2 if status == "VIOLATED" else 0)
    assert "--approved-baseline" not in spec.common_arguments
    manual = replace(spec, name="manual", candidate_arguments=(*spec.candidate_arguments, "--custom-mode", "value"))
    assert manual.candidate_arguments[-2:] == ("--custom-mode", "value")


@pytest.mark.parametrize("name,candidate,profile,status", CASES)
def test_entrypoint_retains_synthetic_campaign(named_runtime: Path, tmp_path: Path,
                                              monkeypatch: pytest.MonkeyPatch, capsys: pytest.CaptureFixture[str],
                                              name: str, candidate: str, profile: str, status: str) -> None:
    """The real writer stores the named spec and nine synthetic pairs without launching verifier source."""
    calls = synthetic_paths(monkeypatch, [-1] * 9)
    output = tmp_path / "new campaign % # ü"
    assert main(command(named_runtime, output, name)) == 0
    summary = json.loads(capsys.readouterr().out)
    assert summary == json.loads((output / "summary.json").read_text())
    assert summary["status"] == "COMPLETE" and summary["completed_pairs"] == 9 and len(calls) == 18
    context = json.loads((output / "campaign.json").read_text())
    assert context["name"] == name and context["specification"]["expected_status"] == status
    assert context["specification"]["timeout_ns"] == 7_000_000_000
    assert context["specification"]["common_arguments"][1] == profile
    first = (output / "pair-01/pair.json").read_bytes()
    with pytest.raises(SystemExit) as error:
        main(command(named_runtime, output, name))
    assert error.value.code == 2 and str(output) in capsys.readouterr().err
    assert (output / "pair-01/pair.json").read_bytes() == first and len(calls) == 18


def test_entrypoint_invalid_summary_returns_failure(named_runtime: Path, tmp_path: Path,
                                                   monkeypatch: pytest.MonkeyPatch,
                                                   capsys: pytest.CaptureFixture[str]) -> None:
    """A retained invalid pair produces a nonzero execution result and no confidence acceptance."""
    synthetic_paths(monkeypatch, [1], invalid_pair=1)
    output = tmp_path / "invalid synthetic"
    assert main(command(named_runtime, output)) == 1
    assert json.loads(capsys.readouterr().out)["status"] == "INVALID"
    assert len(json.loads((output / "pair-01/pair.json").read_text())["paths"]) == 2


@pytest.mark.parametrize("relative", ["bin/migration-check", "python-path", "examples/approved/schema.sql",
    "examples/approved/Requirements.lean", "examples/add_column_then_table/migration.sql",
    "examples/add_column_then_table/NextInterpretation.lean", "examples/add_column_then_table/Proofs.lean"])
def test_missing_selected_files_fail_closed(named_runtime: Path, tmp_path: Path,
                                           capsys: pytest.CaptureFixture[str], relative: str) -> None:
    """Missing selected roles stop before the writer creates campaign evidence."""
    missing = named_runtime / relative
    missing.unlink()
    output = tmp_path / "refused"
    with pytest.raises(SystemExit) as error:
        main(command(named_runtime, output))
    assert error.value.code == 2 and str(missing) in capsys.readouterr().err
    assert not output.exists()


@pytest.mark.parametrize("selection", ["missing-python", "wrong-python", "not-executable", "zero-timeout"])
def test_invalid_configuration_has_no_output(named_runtime: Path, tmp_path: Path,
                                            capsys: pytest.CaptureFixture[str], selection: str) -> None:
    """Only the declared executable interpreter and a positive common timeout can start acquisition."""
    output = tmp_path / "refused configuration"
    values = command(named_runtime, output)
    if selection in ("missing-python", "wrong-python"):
        python = tmp_path / selection
        if selection == "wrong-python":
            python.write_text("synthetic other interpreter")
            python.chmod(0o755)
        values[values.index("--python") + 1] = str(python)
    elif selection == "not-executable":
        (named_runtime / "bin/migration-check").chmod(0o644)
    else:
        values[-1] = "0"
    with pytest.raises(SystemExit) as error:
        main(values)
    assert error.value.code == 2 and capsys.readouterr().err and not output.exists()


@pytest.mark.parametrize("flag", ["--case", "--runtime", "--python", "--output", "--timeout-seconds"])
def test_entrypoint_requires_explicit_inputs(named_runtime: Path, tmp_path: Path,
                                            capsys: pytest.CaptureFixture[str], flag: str) -> None:
    """No ambient runtime, interpreter, timeout or output can become an implicit campaign selection."""
    output = tmp_path / "missing selector"
    values = command(named_runtime, output)
    index = values.index(flag)
    del values[index:index + 2]
    with pytest.raises(SystemExit) as error:
        main(values)
    assert error.value.code == 2 and flag in capsys.readouterr().err and not output.exists()


def test_entrypoint_refuses_output_in_selected_inputs(named_runtime: Path, monkeypatch: pytest.MonkeyPatch,
                                                    capsys: pytest.CaptureFixture[str]) -> None:
    """A complete configuration cannot write campaign data into its recorded runtime or source roots."""
    calls = synthetic_paths(monkeypatch, [-1] * 9)
    output = named_runtime / "examples/approved/refused-campaign"
    with pytest.raises(SystemExit) as error:
        main(command(named_runtime, output))
    message = capsys.readouterr().err
    assert error.value.code == 2 and str(output) in message and str(named_runtime) in message
    assert "outside runtime" in message and not output.exists() and not calls
