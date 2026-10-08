"""Summarize observed source display conditions separately from typed native values."""

from conformance.case_format import Json


def result_evidence(candidate: dict[str, Json], field: str, prefix_field: str) -> dict[str, Json]:
    """Summarize actual successful-call metadata while excluding connection controls."""
    observed: list[int | str | None] = []
    for commands, codes, metadata in (("prefix", "prefixCodes", prefix_field), ("commands", "codes", field)):
        observed.extend(value for command, code, value in
                        zip(candidate[commands], candidate[codes], candidate[metadata], strict=True)
                        if isinstance(command, str) and code == 0)
    return {"values": sorted(set(observed), key=lambda value: (value is not None, value)),
            "successfulCalls": len(observed)}


def result_precision_evidence(candidate: dict[str, Json]) -> dict[str, Json]:
    """Retain the measured precision independently of stored native REAL bits."""
    return result_evidence(candidate, "precisions", "prefixPrecisions")


def result_nullvalue_evidence(candidate: dict[str, Json]) -> dict[str, Json]:
    """Retain measured Tcl NULL display strings independently of native NULL cells."""
    return result_evidence(candidate, "nullValues", "prefixNullValues")
