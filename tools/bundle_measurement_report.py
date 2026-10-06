"""Report complete paired evidence with exact joint/fixed confidence and no implementer time tolerance."""

from collections.abc import Sequence
from dataclasses import asdict
from fractions import Fraction

from migration_check.structural import Json
from tools.bundle_measurement_protocol import PairObservation, next_pair_count
from tools.bundle_measurement_statistics import EXTENDED_PAIRS, INITIAL_PAIRS, median_interval


def fraction_record(value: Fraction) -> dict[str, Json]:
    """Retain exact rational confidence values rather than rounded percentages."""
    return {"numerator": value.numerator, "denominator": value.denominator}


def duration_summary(values: Sequence[int]) -> dict[str, Json]:
    """Use integer order statistics for the odd nine/25 samples and retain the complete range."""
    ordered = sorted(values)
    return {"median_ns": ordered[len(ordered) // 2], "minimum_ns": ordered[0], "maximum_ns": ordered[-1]}


def look_record(pairs: Sequence[PairObservation]) -> dict[str, Json]:
    """Retain each declared nine/25 look with its own path medians and exact confidence calculation."""
    differences: list[int] = []
    durations: dict[str, list[int]] = {"verify": [], "bundle": []}
    for pair in pairs:
        if type(pair.difference_ns) is not int:
            raise ValueError("Complete confidence look contains a missing integer paired difference")
        differences.append(pair.difference_ns)
        for path in pair.paths:
            wall = path.wall_ns()
            if type(wall) is not int:
                raise ValueError("Complete confidence look contains an unexecuted path")
            durations[path.flow].append(wall)
    interval = median_interval(differences)
    interval_record = asdict(interval)
    for key in ("fixed_coverage", "joint_coverage", "required_joint_coverage"):
        interval_record[key] = fraction_record(interval_record[key])
    return {"paths": {flow: duration_summary(walls) for flow, walls in durations.items()},
            "paired_difference": interval_record}


def summarize_pairs(pairs: Sequence[PairObservation]) -> dict[str, Json]:
    """Any invalid pair suppresses timing acceptance while every raw difference/condition remains visible."""
    invalid: dict[str, Json] = {str(pair.number): list(pair.invalid_conditions) for pair in pairs if pair.invalid_conditions}
    report: dict[str, Json] = {"completed_pairs": len(pairs), "invalid_pairs": invalid,
        "differences_ns": [pair.difference_ns for pair in pairs], "owner_review": "required for every result",
        "cutover": "not performed by this harness"}
    if invalid:
        return {**report, "status": "INVALID", "decision": "retain both paths; report the documented conditions"}
    target = next_pair_count(pairs)
    looks: dict[str, Json] = {}
    if len(pairs) >= INITIAL_PAIRS:
        looks[str(INITIAL_PAIRS)] = look_record(pairs[:INITIAL_PAIRS])
    if len(pairs) == EXTENDED_PAIRS:
        looks[str(EXTENDED_PAIRS)] = look_record(pairs)
    report["looks"] = looks
    if len(pairs) != target:
        return {**report, "status": "INCOMPLETE", "required_pairs": target}
    final = look_record(pairs)
    interval = final["paired_difference"]
    if not isinstance(interval, dict):
        raise ValueError("Complete confidence report has no interval object")
    verdict = interval["verdict"]
    decision = ("owner decision required for regression" if verdict == "REGRESSION" else
                "unresolved interval prevents cutover" if verdict == "UNRESOLVED" else
                "no observed slowdown under the predeclared confidence rule; owner review required")
    return {**report, "status": "COMPLETE", **final, "decision": decision}
