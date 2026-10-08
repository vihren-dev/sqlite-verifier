"""Exact median bounds for the approved nine-to-25 paired cold-run protocol."""

from collections.abc import Sequence
from dataclasses import dataclass
from fractions import Fraction
from math import comb
from typing import Literal

INITIAL_PAIRS = 9
"""Approved initial count of paired cold trials."""
EXTENDED_PAIRS = 25
"""Approved final count, including the initial nine pairs."""
INITIAL_RANK = 2
"""First-look endpoints are ordered differences two and eight."""
EXTENDED_RANK = 7
"""Final endpoints seven and 19 retain joint coverage across both looks."""
REQUIRED_JOINT_COVERAGE = Fraction(95, 100)
"""The selected nine-or-25 result must cover the median with at least this probability."""
Verdict = Literal["REGRESSION", "NO_SLOWDOWN", "UNRESOLVED"]


@dataclass(frozen=True)
class MedianInterval:
    """Keep integer nanosecond bounds and exact fixed-size/joint confidence separately."""

    pairs: int
    rank: int
    minimum_ns: int
    maximum_ns: int
    median_ns: int
    lower_ns: int
    upper_ns: int
    fixed_coverage: Fraction
    joint_coverage: Fraction
    required_joint_coverage: Fraction
    verdict: Verdict


def fixed_coverage(pairs: int, rank: int) -> Fraction:
    """Return exact sign coverage of ordered endpoints rank and pairs-rank+1.

    Independent observations around a continuous median give this probability;
    ties at the median make the bounds conservative.
    """
    if type(pairs) is not int or type(rank) is not int or not 1 <= rank <= (pairs + 1) // 2:
        raise ValueError("Invalid median rank or pair count; use an interior order-statistic bound")
    return Fraction(2**pairs - 2 * sum(comb(pairs, index) for index in range(rank)), 2**pairs)


def joint_coverage(initial_rank: int = INITIAL_RANK, extended_rank: int = EXTENDED_RANK) -> Fraction:
    """Return the probability that both nested intervals cover the median for these ranks.

    The predeclared default ranks meet the required 95% joint coverage.
    """
    fixed_coverage(INITIAL_PAIRS, initial_rank)
    fixed_coverage(EXTENDED_PAIRS, extended_rank)
    failed = 0
    for first in range(INITIAL_PAIRS + 1):
        for extra in range(EXTENDED_PAIRS - INITIAL_PAIRS + 1):
            total = first + extra
            if (first < initial_rank or first > INITIAL_PAIRS - initial_rank
                    or total < extended_rank or total > EXTENDED_PAIRS - extended_rank):
                failed += comb(INITIAL_PAIRS, first) * comb(EXTENDED_PAIRS - INITIAL_PAIRS, extra)
    return Fraction(2**EXTENDED_PAIRS - failed, 2**EXTENDED_PAIRS)


def median_interval(differences_ns: Sequence[int]) -> MedianInterval:
    """Classify bundle-minus-verify differences using all pairs and the predeclared joint bounds."""
    count = len(differences_ns)
    invalid = next(((index, type(value).__name__) for index, value in enumerate(differences_ns)
                    if type(value) is not int), None)
    if count not in (INITIAL_PAIRS, EXTENDED_PAIRS) or invalid is not None:
        detail = "none" if invalid is None else f"index {invalid[0]} has type {invalid[1]}"
        raise ValueError(f"Expected nine or 25 integer paired differences; received {count}; "
                         f"first non-integer: {detail}. Preserve every complete raw pair")
    ordered = sorted(differences_ns)
    rank = INITIAL_RANK if count == INITIAL_PAIRS else EXTENDED_RANK
    lower, upper = ordered[rank - 1], ordered[-rank]
    verdict: Verdict = "REGRESSION" if lower > 0 else "NO_SLOWDOWN" if upper <= 0 else "UNRESOLVED"
    return MedianInterval(count, rank, ordered[0], ordered[-1], ordered[count // 2], lower, upper,
                          fixed_coverage(count, rank), joint_coverage(), REQUIRED_JOINT_COVERAGE, verdict)


def required_pairs(result: MedianInterval) -> int:
    """Extend an unresolved nine-pair record while retaining its initial pairs; never add a third look."""
    return EXTENDED_PAIRS if result.pairs == INITIAL_PAIRS and result.verdict == "UNRESOLVED" else result.pairs
