"""Apply only the predeclared alternating nine-to-25 policy to complete retained pairs."""

from collections.abc import Sequence
from dataclasses import dataclass

from tools.bundle_measurement_paths import Flow, PathObservation
from tools.bundle_measurement_statistics import EXTENDED_PAIRS, INITIAL_PAIRS, median_interval, required_pairs


def pair_order(number: int) -> tuple[Flow, Flow]:
    """Start odd pairs with verify and even pairs with bundle, without changing either path's inputs."""
    if type(number) is not int or number < 1:
        raise ValueError("Paired trial number must be a positive integer")
    return ("verify", "bundle") if number % 2 else ("bundle", "verify")


@dataclass(frozen=True)
class PairObservation:
    """Both paths and any invalid conditions remain attached to their actual invocation order."""

    number: int
    order: tuple[Flow, Flow]
    paths: tuple[PathObservation, PathObservation]
    difference_ns: int | None
    invalid_conditions: tuple[str, ...]


def observed_pair(number: int, paths: tuple[PathObservation, PathObservation]) -> PairObservation:
    """Compute bundle-minus-verify from whole measured paths only when both observations are valid."""
    expected = pair_order(number)
    if tuple(path.flow for path in paths) != expected:
        raise ValueError(f"Pair {number} does not use its predeclared order {expected}")
    invalid = [f"{path.flow}: {condition}" for path in paths for condition in path.invalid_conditions]
    if paths[0].filesystem_device != paths[1].filesystem_device:
        invalid.append("paired paths use different temporary filesystems")
    walls = {path.flow: path.wall_ns() for path in paths}
    if any(type(wall) is not int or wall < 0 for wall in walls.values()):
        invalid.append("complete measured path interval is missing or invalid")
    difference = None if invalid else walls["bundle"] - walls["verify"]
    return PairObservation(number, expected, paths, difference, tuple(invalid))


def next_pair_count(pairs: Sequence[PairObservation]) -> int:
    """Never peek at another sample count or replace initial pairs; invalid evidence stops the campaign."""
    if len(pairs) > EXTENDED_PAIRS:
        raise ValueError("Campaign contains more than the predeclared 25 pairs")
    for number, pair in enumerate(pairs, start=1):
        if pair.number != number or pair.order != pair_order(number):
            raise ValueError("Paired evidence is reordered or has a missing trial number")
        if pair.invalid_conditions or type(pair.difference_ns) is not int:
            raise ValueError(f"Pair {number} is invalid; retain both paths and report its conditions")
    if len(pairs) < INITIAL_PAIRS:
        return INITIAL_PAIRS
    initial = median_interval([pair.difference_ns for pair in pairs[:INITIAL_PAIRS]])
    target = required_pairs(initial)
    if len(pairs) > INITIAL_PAIRS and target == INITIAL_PAIRS:
        raise ValueError("Extra trials follow a decisive nine-pair result; the predeclared rule did not authorize them")
    return target
