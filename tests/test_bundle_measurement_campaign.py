"""Actual campaign persistence uses synthetic intervals; these tests are not performance evidence."""

from collections.abc import Sequence
import gzip
import json
from pathlib import Path

import pytest

from migration_check.structural import Json
from tests.bundle_measurement_fixture import launcher
from tests.bundle_measurement_path_fixture import trial_spec
from tests.bundle_measurement_campaign_fixture import synthetic_paths
import tools.bundle_measurement_campaign as campaign
from tools.bundle_measurement_paths import Flow, TrialSpec
from tools.bundle_measurement_protocol import PairObservation, pair_order


def read(path: Path) -> dict[str, Json]:
    """Inspect the actual persisted record, rather than only the writer's return value."""
    return json.loads(path.read_text())


@pytest.mark.parametrize("difference,verdict", [(1, "REGRESSION"), (-1, "NO_SLOWDOWN"), (0, "NO_SLOWDOWN")])
def test_decisive_nine_persists_both_paths_and_context(trial_spec: TrialSpec, tmp_path: Path,
                                                     monkeypatch: pytest.MonkeyPatch, difference: int,
                                                     verdict: str) -> None:
    """Nine real pair files retain alternating paths, identities and the unchanged confidence policy."""
    calls = synthetic_paths(monkeypatch, [difference] * 9)
    output = tmp_path / "campaign"
    summary = campaign.run_campaign(trial_spec, output)
    assert read(output / "summary.json") == summary
    assert summary["status"] == "COMPLETE" and summary["completed_pairs"] == 9
    assert summary["paired_difference"]["verdict"] == verdict
    assert summary["differences_ns"] == [difference] * 9
    assert summary["paired_difference"]["joint_coverage"] == {"numerator": 1994151, "denominator": 2097152}
    assert calls == [(number, flow) for number in range(1, 10) for flow in pair_order(number)]
    context = read(output / "campaign.json")
    assert context["name"] == trial_spec.name and context["state"] == "COMPLETE"
    assert context["specification"]["runtime"] == str(trial_spec.runtime)
    assert json.loads(gzip.decompress(Path(context["identity"]).read_bytes())) == trial_spec.identity()
    for number in range(1, 10):
        pair = read(output / f"pair-{number:02d}/pair.json")
        assert pair["number"] == number and pair["state"] == "COMPLETE"
        assert pair["order"] == list(pair_order(number)) and pair["difference_ns"] == difference
        assert [path["flow"] for path in pair["paths"]] == list(pair_order(number))
        assert all(Path(path["artifacts"]).is_file() for path in pair["paths"])
    assert not (output / "pair-10").exists()


def test_same_nine_are_preserved_through_25(trial_spec: TrialSpec, tmp_path: Path,
                                          monkeypatch: pytest.MonkeyPatch) -> None:
    """The writer extends an unresolved first look without replacing or rewriting any initial pair."""
    differences = list(range(-4, 5)) + [0] * 16
    calls = synthetic_paths(monkeypatch, differences)
    output = tmp_path / "extended"
    first_nine: dict[str, bytes] = {}
    summarize = campaign.summarize_pairs

    def retain_first_look(pairs: Sequence[PairObservation]) -> dict[str, Json]:
        """Capture actual first-look file bytes before the writer acquires its extension."""
        if len(pairs) == 9:
            first_nine.update({path.name + str(path.parent): path.read_bytes()
                              for path in output.glob("pair-*/pair.json")})
        return summarize(pairs)

    monkeypatch.setattr(campaign, "summarize_pairs", retain_first_look)
    result = campaign.run_campaign(trial_spec, output)
    assert result["status"] == "COMPLETE" and result["completed_pairs"] == 25
    assert result["differences_ns"] == differences and len(calls) == 50
    assert result["looks"]["9"]["paired_difference"]["verdict"] == "UNRESOLVED"
    assert result["looks"]["25"]["paired_difference"]["rank"] == 7
    assert len(first_nine) == 9
    assert all(path.read_bytes() == first_nine[path.name + str(path.parent)]
               for path in sorted(output.glob("pair-*/pair.json"))[:9])
    assert not (output / "pair-26").exists()


def test_invalid_pair_stops_after_retaining_both_paths(trial_spec: TrialSpec, tmp_path: Path,
                                                     monkeypatch: pytest.MonkeyPatch) -> None:
    """An invalid first path still retains the second path and suppresses every confidence verdict."""
    calls = synthetic_paths(monkeypatch, [1], invalid_pair=1)
    output = tmp_path / "invalid"
    summary = campaign.run_campaign(trial_spec, output)
    pair = read(output / "pair-01/pair.json")
    assert calls == [(1, "verify"), (1, "bundle")]
    assert pair["state"] == summary["status"] == read(output / "campaign.json")["state"] == "INVALID"
    assert pair["difference_ns"] is None and len(pair["paths"]) == 2
    assert summary["invalid_pairs"]["1"] == ["verify: synthetic invalid condition"]
    assert "paired_difference" not in summary and not (output / "pair-02").exists()


@pytest.mark.parametrize("flow,complete_paths", [("verify", 0), ("bundle", 1)])
def test_interrupted_pair_preserves_partial_raw_evidence(trial_spec: TrialSpec, tmp_path: Path,
                                                       monkeypatch: pytest.MonkeyPatch, flow: Flow,
                                                       complete_paths: int) -> None:
    """An interruption retains completed observations and the unfinished raw path without inventing timing."""
    synthetic_paths(monkeypatch, [1], interruption=(1, flow))
    output = tmp_path / "interrupted"
    with pytest.raises(KeyboardInterrupt, match="synthetic fixture"):
        campaign.run_campaign(trial_spec, output)
    pair = read(output / "pair-01/pair.json")
    summary, context = read(output / "summary.json"), read(output / "campaign.json")
    assert pair["state"] == summary["status"] == context["state"] == "INTERRUPTED"
    assert len(pair["paths"]) == complete_paths and pair["pending_flow"] == flow
    assert pair["difference_ns"] is None and "KeyboardInterrupt" in pair["invalid_conditions"][0]
    assert (output / f"pair-01/{flow}/stdout.bin").read_bytes().startswith(b"synthetic fixture")
    assert summary["completed_pairs"] == 0 and summary["unfinished_pair"] == context["stopped_pair"] == 1
    assert not (output / "pair-02").exists()


def test_machine_change_after_pair_is_durable(trial_spec: TrialSpec, tmp_path: Path,
                                            monkeypatch: pytest.MonkeyPatch) -> None:
    """A changed host invalidates the completed pair while preserving both actual raw path files."""
    synthetic_paths(monkeypatch, [1])
    observed = iter(({"node": "initial"}, {"node": "changed"}))
    monkeypatch.setattr(campaign, "host_identity", lambda: next(observed))
    output = tmp_path / "changed-machine"
    with pytest.raises(ValueError) as error:
        campaign.run_campaign(trial_spec, output)
    assert str(output.resolve()) in str(error.value) and "pair 1" in str(error.value)
    assert "new campaign" in str(error.value)
    pair = read(output / "pair-01/pair.json")
    assert pair["state"] == "INVALID" and pair["difference_ns"] is None
    assert pair["machine_after"] == {"node": "changed"} and len(pair["paths"]) == 2
    assert all((output / f"pair-01/{flow}/stdout.bin").is_file() for flow in ("verify", "bundle"))
    assert read(output / "summary.json")["status"] == read(output / "campaign.json")["state"] == "INVALID"
    assert "Machine identity changed" in read(output / "summary.json")["invalid_pairs"]["1"][0]
