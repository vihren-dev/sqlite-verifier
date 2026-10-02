"""Fixed-denominator scenario counts retain zeros and reject ambiguous requirement credit."""

import json
from pathlib import Path

import pytest

from conformance.case_format import Json
from conformance.progress import progress
from conformance.requirement_coverage import comparison, credited_upstream, resolved_ids

pytestmark = [pytest.mark.unit, pytest.mark.conformance]
FIRST = "R-00001-00002-00003"
SECOND = "R-00001-00004-00005"
THIRD = "R-00006-00007-00008"


@pytest.fixture
def inventory() -> dict[str, Json]:
    """Use an out-of-scope zero row to expose accidental file filtering."""
    return {"count": 3, "requirements": [
        {"id": FIRST, "file": "datatype3.html", "publicTclEvidence": ["a.test"]},
        {"id": SECOND, "file": "lang_transaction.html", "publicTclEvidence": []},
        {"id": THIRD, "file": "fileformat.html", "publicTclEvidence": ["b.test"]}]}


def record(name: str, *tags: str) -> dict[str, Json]:
    """Construct only the evidence needed to count requirement scenarios."""
    return {"name": name, "requirements": list(tags)}


def test_comparison_counts_aliases_once_and_retains_zeros(inventory: dict[str, Json]) -> None:
    """Different aliases share a row, while one case can demonstrate two distinct rows."""
    before = [record("aliases", "R-00001-00002", FIRST, FIRST), record("untagged")]
    after = before + [record("two-rows", FIRST, SECOND)]
    result = comparison(before, after, inventory)
    assert result == {"inventoryCount": 3, "beforeDenominator": 2, "afterDenominator": 3,
        "beforeRowsWithCases": 1, "afterRowsWithCases": 2, "rowsGainingCases": 1,
        "rowsLosingCases": 0, "rows": [
            {"id": FIRST, "file": "datatype3.html", "publicTclEvidence": ["a.test"],
             "beforeCases": 1, "afterCases": 2},
            {"id": SECOND, "file": "lang_transaction.html", "publicTclEvidence": [],
             "beforeCases": 0, "afterCases": 1},
            {"id": THIRD, "file": "fileformat.html", "publicTclEvidence": ["b.test"],
             "beforeCases": 0, "afterCases": 0}]}
    assert comparison(after, before, inventory)["rowsLosingCases"] == 1


@pytest.mark.parametrize("tag", ["R-unknown", "R-00001", ""])
def test_unknown_or_ambiguous_tag_is_refused(inventory: dict[str, Json], tag: str) -> None:
    """Missing and shared prefixes cannot silently grant requirement credit."""
    with pytest.raises(ValueError, match="Unknown or ambiguous requirement tag"):
        comparison([], [record("invalid", tag)], inventory)


@pytest.mark.parametrize("damage", ["count", "duplicate", "boolean-count"])
def test_inconsistent_inventory_is_refused(inventory: dict[str, Json], damage: str) -> None:
    """The stable denominator must name every requirement exactly once."""
    if damage == "duplicate":
        inventory["requirements"][1]["id"] = FIRST
    else:
        inventory["count"] = True if damage == "boolean-count" else 4
    with pytest.raises(ValueError, match="Requirement inventory"):
        resolved_ids([], inventory)


def test_obsolete_citations_retain_provenance_without_credit(inventory: dict[str, Json]) -> None:
    """A corpus freeze preserves native observations while current coverage excludes stale citations."""
    source = {**record("native", FIRST, "R-unknown", "R-00001"),
              "upstream": {"file": "a.test", "sourceSha256": "source-bound"},
              "trace": [{"sql": "SELECT 7", "rows": [[7]]}]}
    credited = credited_upstream([source], inventory)[0]
    assert credited["trace"] == source["trace"] and source["requirements"] == [FIRST, "R-unknown", "R-00001"]
    assert credited["upstream"] == {**source["upstream"], "uncreditedRequirements": ["R-unknown", "R-00001"]}
    assert resolved_ids([credited], inventory) == [{FIRST}]
    report = comparison([], [credited], inventory)
    assert report["afterRowsWithCases"] == 1 and report["inventoryCount"] == 3


@pytest.mark.parametrize("tag", [False, [], ""])
def test_malformed_reference_cannot_be_retained_as_a_citation(inventory: dict[str, Json], tag: Json) -> None:
    """Malformed inputs fail the trust boundary instead of becoming obsolete reference metadata."""
    with pytest.raises(ValueError, match="Unknown or ambiguous requirement tag"):
        credited_upstream([{"requirements": [tag], "upstream": {}}], inventory)


def test_progress_uses_per_case_verdicts(inventory: dict[str, Json], tmp_path: Path,
                                       monkeypatch: pytest.MonkeyPatch) -> None:
    """Short/full tags aggregate distinct cases once and retain the legacy raw tag report."""
    records = [record("aliases", "R-00001-00002", FIRST, FIRST),
               record("second-case", FIRST), record("unsupported", SECOND), record("untagged")]
    raw: dict[str, Json] = {"R-00001-00002": {"AGREE": 1},
        FIRST: {"AGREE": 2, "DISAGREE": 1}, SECOND: {"MODEL_UNSUPPORTED": 1},
        "UNTAGGED": {"HARNESS_ERROR": 1}}
    answers: dict[str, Json] = {"byRequirement": raw, "cases": [
        {"name": case["name"], "verdict": verdict} for case, verdict in zip(records,
        ("AGREE", "DISAGREE", "MODEL_UNSUPPORTED", "HARNESS_ERROR"), strict=True)]}

    def loaded(directory: Path) -> tuple[dict[str, Json], list[dict[str, Json]]]:
        """Avoid unrelated native evidence when testing aggregation."""
        return {"corpusVersion": 1, "casesSha256": "bound-by-load"}, records

    def replayed(cases: list[dict[str, Json]], runtime: Path) -> dict[str, Json]:
        """Supply known case verdicts independently of the raw alias totals."""
        assert cases == records
        return answers

    monkeypatch.setattr("conformance.progress.load", loaded)
    monkeypatch.setattr("conformance.progress.replay", replayed)
    requirements = tmp_path / "requirements.json"
    requirements.write_text(json.dumps(inventory))
    report = progress(tmp_path, requirements, tmp_path)
    assert report["byRequirement"] == raw
    assert report["requirementMatrixRows"] == report["requirementInventoryCount"] == 3
    assert [row["counts"] for row in report["requirementMatrix"]] == [
        {"AGREE": 1, "DISAGREE": 1, "MODEL_UNSUPPORTED": 0, "HARNESS_ERROR": 0},
        {"AGREE": 0, "DISAGREE": 0, "MODEL_UNSUPPORTED": 1, "HARNESS_ERROR": 0},
        {"AGREE": 0, "DISAGREE": 0, "MODEL_UNSUPPORTED": 0, "HARNESS_ERROR": 0}]
    assert "requirement_coverage.py" in report["harnessSha256"]
