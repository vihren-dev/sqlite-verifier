"""The development tier samples identities independently of current or native outcomes."""

from copy import deepcopy
from pathlib import Path

import pytest

from conformance.case_format import Json
from conformance import replay_tiers

pytestmark = pytest.mark.conformance


def membership() -> list[dict[str, Json]]:
    """Use uneven source populations so the per-source minimum is observable."""
    authored = [{"name": f"authored-{part}", "part": part} for part in replay_tiers.AUTHORED_PARTS]
    upstream = [{"name": f"{source}-{index}", "part": "upstream", "upstream": {"file": source}}
                for source, size in (("small.test", 1), ("medium.test", 6), ("large.test", 20))
                for index in range(size)]
    return authored + upstream


def test_selection_is_bounded_stable_and_verdict_independent() -> None:
    """Every authored case and small source survives reordering and changed refusal evidence."""
    records = membership()
    original = replay_tiers.select(records)
    changed = deepcopy(records[::-1])
    for record in changed:
        record.update(nativeAccepted=False, nativeRefusal="changed", verdict="DISAGREE", features=["changed"])
    assert [record["name"] for record in replay_tiers.select(changed)] == [record["name"] for record in original]
    assert len(original) == 3 + 3 + 8
    assert {record["part"] for record in original if record["part"] != "upstream"} == replay_tiers.AUTHORED_PARTS
    assert {record["upstream"]["file"] for record in original if record["part"] == "upstream"} == {
        "small.test", "medium.test", "large.test"}
    assert len({record["name"] for record in original}) == len(original)
    assert replay_tiers.select(records[:3]) == sorted(records[:3], key=lambda record: (record["part"], record["name"]))


def test_small_populations_and_invalid_membership() -> None:
    """The additional quota cannot duplicate cases or conceal malformed source identities."""
    records = [{"name": "one", "part": "upstream", "upstream": {"file": "only.test"}}]
    assert replay_tiers.select(records) == records
    for invalid in (records + records, [{"name": "one", "part": "upstream"}],
                    [{"name": "one", "part": "invented"}]):
        with pytest.raises(ValueError, match="tier"):
            replay_tiers.select(invalid)


@pytest.mark.parametrize("verdict", ["DISAGREE", "HARNESS_ERROR"])
def test_failed_selected_cases_fail_the_tier(monkeypatch: pytest.MonkeyPatch, verdict: str) -> None:
    """A selected oracle or transport failure cannot disappear into unsupported counts."""
    def replay(records: list[dict[str, Json]], runtime: Path) -> dict[str, Json]:
        """Supply the observable public replay result for an injected failure."""
        return {"counts": {verdict: 1}, "cases": [{"name": "failing", "verdict": verdict}]}
    monkeypatch.setattr(replay_tiers, "replay", replay)
    with pytest.raises(ValueError, match="Tier replay failed.*failing"):
        replay_tiers.checked_replay([{"name": "failing"}], Path("unused"))


@pytest.mark.parametrize("defect", ["missing", "renamed", "counts", "unknown"])
def test_replay_requires_an_exact_case_and_verdict_denominator(
        monkeypatch: pytest.MonkeyPatch, defect: str) -> None:
    """Malformed answers cannot make a green sample by dropping or relabeling a case."""
    def replay(records: list[dict[str, Json]], runtime: Path) -> dict[str, Json]:
        """Vary one result contract independently of the selection mechanism."""
        return {"counts": {"MODEL_UNSUPPORTED": 0 if defect == "counts" else 1},
                "cases": [] if defect == "missing" else [{"name": "other" if defect == "renamed" else "case",
                    "verdict": "UNKNOWN" if defect == "unknown" else "MODEL_UNSUPPORTED"}]}
    monkeypatch.setattr(replay_tiers, "replay", replay)
    with pytest.raises(ValueError, match="Tier replay"):
        replay_tiers.checked_replay([{"name": "case"}], Path("unused"))


def test_unsupported_stays_explicit(monkeypatch: pytest.MonkeyPatch) -> None:
    """Unsupported is a valid measurement, never an implicit agreement."""
    def replay(records: list[dict[str, Json]], runtime: Path) -> dict[str, Json]:
        """Keep the supplied unsupported result and its diagnostics intact."""
        return {"counts": {"MODEL_UNSUPPORTED": 1},
                "cases": [{"name": "case", "verdict": "MODEL_UNSUPPORTED", "diagnostics": ["profile"]}]}
    monkeypatch.setattr(replay_tiers, "replay", replay)
    result = replay_tiers.checked_replay([{"name": "case"}], Path("unused"))
    assert result["counts"] == {"MODEL_UNSUPPORTED": 1}
    assert result["cases"][0]["diagnostics"] == ["profile"]


@pytest.mark.parametrize("missing", ["build/sqlite-parser", ".lake/build/bin/conformance-runner"])
def test_missing_runtime_fails_even_before_unsupported_replay(tmp_path: Path, missing: str) -> None:
    """A sample cannot pass against an incomplete artifact just because it admits no cases."""
    for relative in ("build/sqlite-parser", ".lake/build/bin/conformance-runner"):
        if relative != missing:
            path = tmp_path / relative
            path.parent.mkdir(parents=True)
            path.write_text("#!/bin/sh\nexit 0\n")
            path.chmod(0o755)
    with pytest.raises(ValueError, match="Tier runtime executable.*" + missing):
        replay_tiers.report(Path("unused-generic"), Path("unused-synthetic"), tmp_path)
