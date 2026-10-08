"""Synthetic integer-nanosecond pairs isolate continuation arithmetic from actual process timing."""

from tools.bundle_measurement_paths import PathObservation
from tools.bundle_measurement_protocol import PairObservation, observed_pair, pair_order


def synthetic_pair(number: int, difference: int, *, invalid: bool = False) -> PairObservation:
    """Build explicitly synthetic complete-path intervals; these are never performance receipts."""
    start = 10_000_000 * number
    old = PathObservation("verify", start, start + 1_000_000, (), (), "before", "after", "artifacts", (), 1, {}, {})
    new = PathObservation("bundle", start + 2_000_000, start + 3_000_000 + difference, (),
                          ("synthetic invalid condition",) if invalid else (), "before", "after", "artifacts", (), 1, {}, {})
    return observed_pair(number, (old, new) if pair_order(number)[0] == "verify" else (new, old))
