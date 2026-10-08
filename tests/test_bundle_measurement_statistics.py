"""The actual two-look decision rule retains at least 95% median coverage, including ties."""

from fractions import Fraction
from math import comb
from collections.abc import Sequence
from typing import cast

import pytest

from tools.bundle_measurement_statistics import (REQUIRED_JOINT_COVERAGE, fixed_coverage, joint_coverage,
                                                 median_interval, required_pairs)


def test_order_statistic_bounds_and_exact_coverages() -> None:
    """Independently enumerated sign outcomes justify the chosen ranks before observations exist."""
    result = median_interval(list(range(1, 10)))
    assert (result.rank, result.lower_ns, result.median_ns, result.upper_ns) == (2, 2, 5, 8)
    assert result.fixed_coverage == Fraction(123, 128)
    extended = median_interval(list(range(1, 26)))
    assert (extended.rank, extended.lower_ns, extended.median_ns, extended.upper_ns) == (7, 7, 13, 19)
    assert extended.fixed_coverage == Fraction(8_265_855, 8_388_608)
    signs = {count: comb(9, count) for count in range(10)}
    extensions = {count: comb(16, count) for count in range(17)}
    covered = sum(first_weight * extra_weight for first, first_weight in signs.items()
                  for extra, extra_weight in extensions.items() if 2 <= first <= 7 and 7 <= first + extra <= 18)
    assert result.joint_coverage == extended.joint_coverage == Fraction(covered, 2**25)
    assert result.required_joint_coverage == REQUIRED_JOINT_COVERAGE == Fraction(95, 100)
    assert result.joint_coverage >= REQUIRED_JOINT_COVERAGE
    assert joint_coverage(2, 8) < REQUIRED_JOINT_COVERAGE
    assert fixed_coverage(9, 3) < REQUIRED_JOINT_COVERAGE
    assert joint_coverage(2, 8) < joint_coverage(2, 7)


@pytest.mark.parametrize("values,verdict,next_count", [
    ([1] * 9, "REGRESSION", 9),
    ([-1] * 9, "NO_SLOWDOWN", 9),
    ([0] * 9, "NO_SLOWDOWN", 9),
    (list(range(-4, 5)), "UNRESOLVED", 25),
    ([0] * 8 + [1], "NO_SLOWDOWN", 9),
    ([0] + [1] * 8, "REGRESSION", 9),
    ([-1] + [0] * 7 + [1], "NO_SLOWDOWN", 9),
    (list(range(-12, 13)), "UNRESOLVED", 25),
])
def test_no_tolerance_or_unapproved_trial_count(values: list[int], verdict: str, next_count: int) -> None:
    """Even one-nanosecond bounds use the stated signs; zero and unresolved bounds retain their meaning."""
    result = median_interval(values)
    assert result.verdict == verdict and required_pairs(result) == next_count
    assert result.minimum_ns == min(values) and result.maximum_ns == max(values)


def tied_sign_counts(pairs: int) -> list[tuple[int, int, int]]:
    """Enumerate a median atom with masses 1/4 below, 1/2 equal and 1/4 above the median."""
    return [(negative, positive, comb(pairs, negative) * comb(pairs - negative, positive)
             * 2**(pairs - negative - positive))
            for negative in range(pairs + 1) for positive in range(pairs - negative + 1)]


def test_ties_make_nested_bounds_conservative() -> None:
    """An exact trinomial calculation verifies both intervals still contain the true tied median."""
    first, extra = tied_sign_counts(9), tied_sign_counts(16)
    assert sum(weight for _, _, weight in first) == 4**9
    covered = sum(weight_a * weight_b for negative_a, positive_a, weight_a in first
                  for negative_b, positive_b, weight_b in extra
                  if negative_a <= 7 and positive_a <= 7
                  and negative_a + negative_b <= 18 and positive_a + positive_b <= 18)
    assert Fraction(covered, 4**25) >= joint_coverage() >= REQUIRED_JOINT_COVERAGE


@pytest.mark.parametrize("values", [[], [0] * 8, [0] * 10, [0] * 24, [0] * 26,
                                     [False] * 9, [1.0] * 9])
def test_invalid_protocol_data_is_refused(values: list[object]) -> None:
    """Incomplete counts and noninteger evidence cannot become a published median claim."""
    with pytest.raises(ValueError, match="nine or 25 integer paired differences"):
        median_interval(cast(Sequence[int], values))


@pytest.mark.parametrize("pairs,rank", [(9, 0), (9, 6), (25, 14), (9, True), (True, 1), (9, 1.0)])
def test_invalid_fixed_size_policy_is_refused(pairs: object, rank: object) -> None:
    """Invalid rank/count data cannot become a confidence probability."""
    with pytest.raises(ValueError, match="Invalid median rank or pair count"):
        fixed_coverage(cast(int, pairs), cast(int, rank))


@pytest.mark.parametrize("initial,extended", [(0, 7), (6, 7), (True, 7), (2, 0), (2, 14), (2, True)])
def test_invalid_joint_policy_is_refused(initial: object, extended: object) -> None:
    """Both looks validate ranks before computing the nested sign distribution."""
    with pytest.raises(ValueError, match="Invalid median rank or pair count"):
        joint_coverage(cast(int, initial), cast(int, extended))


def test_bad_difference_names_count_index_and_type() -> None:
    """The operator can find the invalid evidence without guessing which pair to inspect."""
    with pytest.raises(ValueError, match="received 9; first non-integer: index 4 has type bool"):
        median_interval([0, 0, 0, 0, False, 0, 0, 0, 0])
