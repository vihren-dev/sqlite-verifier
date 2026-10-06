"""The actual nine-to-25 stopping rule retains every original pair and uses only declared looks."""

from dataclasses import replace

import pytest

from tests.bundle_measurement_pair_fixture import synthetic_pair
from tools.bundle_measurement_protocol import next_pair_count, observed_pair, pair_order
from tools.bundle_measurement_report import summarize_pairs


@pytest.mark.parametrize("number,order", [(1, ("verify", "bundle")), (2, ("bundle", "verify")),
    (3, ("verify", "bundle")), (9, ("verify", "bundle")), (25, ("verify", "bundle")), (26, ("bundle", "verify"))])
def test_alternating_order(number: int, order: tuple[str, str]) -> None:
    """Each consecutive pair switches which complete path runs first."""
    assert pair_order(number) == order


@pytest.mark.parametrize("number", [0, -1, True, 1.5])
def test_invalid_pair_number(number: object) -> None:
    """A missing/noninteger ordinal cannot acquire an implicit order."""
    with pytest.raises(ValueError, match="positive integer"):
        pair_order(number)


@pytest.mark.parametrize("differences,verdict", [([1] * 9, "REGRESSION"), ([-1] * 9, "NO_SLOWDOWN"), ([0] * 9, "NO_SLOWDOWN")])
def test_decisive_nine_never_extends(differences: list[int], verdict: str) -> None:
    """A decisive first look preserves its nine raw differences and has no third count or tolerance."""
    pairs = [synthetic_pair(index, value) for index, value in enumerate(differences, 1)]
    for count in range(9):
        assert next_pair_count(pairs[:count]) == 9 and summarize_pairs(pairs[:count])["status"] == "INCOMPLETE"
    report = summarize_pairs(pairs)
    assert next_pair_count(pairs) == 9 and report["status"] == "COMPLETE"
    assert report["paired_difference"]["verdict"] == verdict and report["differences_ns"] == differences
    assert report["cutover"] == "not performed by this harness"
    assert report["paired_difference"]["fixed_coverage"] == {"numerator": 123, "denominator": 128}
    assert report["paired_difference"]["joint_coverage"] == {"numerator": 1994151, "denominator": 2097152}


def test_unresolved_extends_original_nine_and_stops_at_25() -> None:
    """The 16 extra pairs extend the original stream, retaining first/final looks and full ranges."""
    differences = [-4, -3, -2, -1, 0, 1, 2, 3, 4] + [0] * 16
    pairs = [synthetic_pair(index, value) for index, value in enumerate(differences, 1)]
    for count in range(9, 26):
        report = summarize_pairs(pairs[:count])
        assert next_pair_count(pairs[:count]) == 25
        assert report["differences_ns"] == differences[:count]
        assert report["looks"]["9"]["paired_difference"]["verdict"] == "UNRESOLVED"
        assert report["status"] == ("COMPLETE" if count == 25 else "INCOMPLETE")
    assert report["paired_difference"]["verdict"] == "NO_SLOWDOWN"
    assert report["paired_difference"]["minimum_ns"] == -4 and report["paired_difference"]["maximum_ns"] == 4
    assert report["looks"]["25"]["paired_difference"]["rank"] == 7
    assert report["paired_difference"]["fixed_coverage"] == {"numerator": 8265855, "denominator": 8388608}


def test_unresolved_25_explicitly_prevents_cutover() -> None:
    """A final interval spanning zero remains unresolved without adding a tolerance or another look."""
    differences = [-1] * 4 + [0] + [1] * 4 + [-1] * 8 + [1] * 8
    pairs = [synthetic_pair(index, value) for index, value in enumerate(differences, 1)]
    report = summarize_pairs(pairs)
    assert report["paired_difference"]["verdict"] == "UNRESOLVED"
    assert report["decision"] == "unresolved interval prevents cutover" and len(report["differences_ns"]) == 25


def test_invalid_pair_is_retained_and_suppresses_acceptance() -> None:
    """An invalid pair keeps both raw paths and its reason instead of disappearing as a slow outlier."""
    pairs = [synthetic_pair(1, 1), synthetic_pair(2, 999_999_999, invalid=True)]
    report = summarize_pairs(pairs)
    assert report["status"] == "INVALID" and report["differences_ns"] == [1, None]
    assert "synthetic invalid condition" in report["invalid_pairs"]["2"][0]
    assert "paired_difference" not in report and len(pairs[1].paths) == 2
    with pytest.raises(ValueError, match="Pair 2 is invalid"):
        next_pair_count(pairs)


def test_reordered_missing_extra_or_wrong_filesystem_refused() -> None:
    """Identity/order conditions apply to all raw pairs before any confidence decision."""
    pair = synthetic_pair(1, 0)
    with pytest.raises(ValueError, match="missing trial number"):
        next_pair_count([replace(pair, number=2)])
    with pytest.raises(ValueError, match="predeclared order"):
        observed_pair(1, tuple(reversed(pair.paths)))
    with pytest.raises(ValueError, match="did not authorize"):
        next_pair_count([synthetic_pair(index, 0) for index in range(1, 11)])
    with pytest.raises(ValueError, match="more than"):
        next_pair_count([synthetic_pair(index, 0) for index in range(1, 27)])
    bad = observed_pair(1, (pair.paths[0], replace(pair.paths[1], filesystem_device=2)))
    assert bad.difference_ns is None and "different temporary filesystems" in bad.invalid_conditions[0]
