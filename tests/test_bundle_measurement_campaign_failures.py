"""Campaign refusal and interrupted metadata keep existing files and durable failure conditions."""

from dataclasses import replace
import json
from pathlib import Path

import pytest

from migration_check.structural import Json
from tests.bundle_measurement_fixture import launcher
from tests.bundle_measurement_path_fixture import trial_spec
from tests.bundle_measurement_campaign_fixture import synthetic_paths
import tools.bundle_measurement_campaign as campaign
from tools.bundle_measurement_identity import tree_identity
from tools.bundle_measurement_paths import TrialSpec


@pytest.mark.parametrize("selected", ["runtime", "source"])
def test_output_root_refusal_has_path_and_action(trial_spec: TrialSpec, tmp_path: Path, selected: str) -> None:
    """Refused output leaves the selected input tree unchanged and identifies the external-root remedy."""
    root = trial_spec.runtime if selected == "runtime" else tmp_path / "source"
    if selected == "source":
        root.mkdir()
        trial_spec = replace(trial_spec, input_roots=(root,))
    before = tree_identity(root)
    output = root / "evidence"
    with pytest.raises(ValueError) as error:
        campaign.run_campaign(trial_spec, output)
    assert str(output.resolve()) in str(error.value) and str(root.resolve()) in str(error.value)
    assert "outside runtime and source inputs" in str(error.value)
    assert not output.exists() and tree_identity(root) == before


@pytest.mark.parametrize("writer", ["campaign", "pair"])
def test_existing_evidence_is_never_overwritten(trial_spec: TrialSpec, tmp_path: Path, writer: str) -> None:
    """Neither writer can overwrite a previously retained incomplete directory."""
    output = tmp_path / "existing"
    output.mkdir()
    previous = output / "raw.bin"
    previous.write_bytes(b"retained existing evidence")
    with pytest.raises(ValueError, match="preserve it.*new evidence directory") as error:
        if writer == "campaign":
            campaign.run_campaign(trial_spec, output)
        else:
            campaign.execute_pair(trial_spec, 1, output, {})
    assert str(output) in str(error.value)
    assert list(output.iterdir()) == [previous] and previous.read_bytes() == b"retained existing evidence"


def test_output_creation_failure_identifies_root(trial_spec: TrialSpec, tmp_path: Path) -> None:
    """A nonexistent parent is an actionable output error, rather than an unexplained campaign failure."""
    output = tmp_path / "missing-parent/campaign"
    with pytest.raises(ValueError) as error:
        campaign.run_campaign(trial_spec, output)
    assert str(output) in str(error.value) and "writable evidence root" in str(error.value)
    assert not output.exists()


def test_interruption_preserves_previous_complete_pair(trial_spec: TrialSpec, tmp_path: Path,
                                                      monkeypatch: pytest.MonkeyPatch) -> None:
    """A second-pair interruption cannot discard the previous pair or invent a completed second interval."""
    calls = synthetic_paths(monkeypatch, [1, 1], interruption=(2, "verify"))
    output = tmp_path / "interrupted-second"
    with pytest.raises(KeyboardInterrupt):
        campaign.run_campaign(trial_spec, output)
    summary = json.loads((output / "summary.json").read_text())
    first = json.loads((output / "pair-01/pair.json").read_text())
    second = json.loads((output / "pair-02/pair.json").read_text())
    assert summary["completed_pairs"] == 1 and summary["differences_ns"] == [1]
    assert summary["unfinished_pair"] == 2 and summary["status"] == "INTERRUPTED"
    assert first["state"] == "COMPLETE" and first["difference_ns"] == 1
    assert second["state"] == "INTERRUPTED" and len(second["paths"]) == 1
    assert calls == [(1, "verify"), (1, "bundle"), (2, "bundle"), (2, "verify")]
    assert not (output / "pair-03").exists()


def test_failed_metadata_replace_preserves_previous_record(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    """A simulated output failure keeps the preceding valid JSON and the unfinished replacement bytes."""
    output = tmp_path / "summary.json"
    output.write_text('{"state":"previous"}')

    def refuse_replace(source: Path, target: Path) -> Path:
        """Inject a deterministic output error without changing real directory permissions."""
        raise PermissionError("synthetic replacement refusal")

    monkeypatch.setattr(Path, "replace", refuse_replace)
    with pytest.raises(ValueError) as error:
        campaign.write_record(output, {"state": "next"})
    assert str(output) in str(error.value) and "writable evidence root" in str(error.value)
    assert json.loads(output.read_text()) == {"state": "previous"}
    pending = list(tmp_path.glob("summary.json.*.pending"))
    assert len(pending) == 1 and json.loads(pending[0].read_text()) == {"state": "next"}


def test_machine_observation_failure_preserves_completed_pair(trial_spec: TrialSpec, tmp_path: Path,
                                                            monkeypatch: pytest.MonkeyPatch) -> None:
    """Failure to observe the host after both paths cannot leave an apparently valid retained pair."""
    synthetic_paths(monkeypatch, [1])
    calls = 0

    def unavailable_after_pair() -> dict[str, Json]:
        """Inject a deterministic host-read failure after the initial campaign identity."""
        nonlocal calls
        calls += 1
        if calls == 1:
            return {"node": "initial"}
        raise OSError("synthetic host observation failure")

    monkeypatch.setattr(campaign, "host_identity", unavailable_after_pair)
    output = tmp_path / "unobserved-machine"
    with pytest.raises(OSError, match="synthetic host"):
        campaign.run_campaign(trial_spec, output)
    pair = json.loads((output / "pair-01/pair.json").read_text())
    summary = json.loads((output / "summary.json").read_text())
    assert pair["state"] == summary["status"] == "INVALID"
    assert pair["difference_ns"] is None and len(pair["paths"]) == 2
    assert summary["completed_pairs"] == 1 and "host observation failure" in pair["invalid_conditions"][0]


def test_unserializable_metadata_preserves_previous_record(tmp_path: Path) -> None:
    """A record-format error identifies its output and retains the previous valid metadata."""
    output = tmp_path / "campaign.json"
    output.write_text('{"state":"previous"}')
    with pytest.raises(ValueError) as error:
        campaign.write_record(output, {"unsupported": Path("synthetic unsupported value")})
    assert str(output) in str(error.value) and "correct the record values" in str(error.value)
    assert json.loads(output.read_text()) == {"state": "previous"}


@pytest.mark.parametrize("error_type,state", [(OSError, "INVALID"), (SystemExit, "INTERRUPTED")])
def test_path_exception_kind_is_durable(trial_spec: TrialSpec, tmp_path: Path,
                                       monkeypatch: pytest.MonkeyPatch, error_type: type[BaseException],
                                       state: str) -> None:
    """Ordinary path errors and explicit exits retain distinct pair/campaign states and their original condition."""
    synthetic_paths(monkeypatch, [1], interruption=(1, "bundle"),
                    interruption_error=error_type("synthetic fixture path failure"))
    output = tmp_path / "path-failed"
    with pytest.raises(error_type, match="synthetic fixture"):
        campaign.run_campaign(trial_spec, output)
    pair = json.loads((output / "pair-01/pair.json").read_text())
    summary = json.loads((output / "summary.json").read_text())
    context = json.loads((output / "campaign.json").read_text())
    assert pair["state"] == summary["status"] == context["state"] == state
    assert pair["difference_ns"] is None and len(pair["paths"]) == 1
    assert error_type.__name__ in pair["invalid_conditions"][0]
    assert error_type.__name__ in summary["invalid_pairs"]["1"][0] == context["condition"]
    assert all((output / f"pair-01/{flow}/stdout.bin").is_file() for flow in ("verify", "bundle"))
    assert not (output / "pair-02").exists()
