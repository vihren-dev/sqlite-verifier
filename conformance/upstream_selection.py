"""Keep acquisition exclusions independent of corpus size and sampling policy."""

from conformance.case_format import Json


def candidate_reasons(candidate: dict[str, Json], *, selected: int, limit: int) -> list[str]:
    """Report all known barriers; a selection limit never hides a fidelity failure."""
    reasons = set(candidate["exclusions"])
    if candidate["failed"]:
        reasons.add("upstream Tcl expectation failed")
    if not candidate["commands"]:
        reasons.add("no SQL observation")
    if any(candidate["codes"][:-1]):
        reasons.add("assertion continues after a SQL error")
    if selected >= limit:
        reasons.add("bounded pilot selection limit")
    return sorted(reasons)
