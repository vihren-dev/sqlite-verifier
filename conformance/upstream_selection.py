"""Keep acquisition exclusions independent of corpus size and sampling policy."""

from conformance.case_format import Json
def candidate_reasons(candidate: dict[str, Json], *, selected: int, limit: int | None,
                      sampling_reason: str | None = None) -> list[str]:
    """Report all known barriers; a selection limit never hides a fidelity failure."""
    reasons = set(candidate["exclusions"])
    if candidate["failed"]:
        reasons.add("upstream Tcl expectation failed")
    if not candidate["commands"]:
        reasons.add("no SQL observation")
    if any(candidate["codes"][:-1]):
        reasons.add("assertion continues after a SQL error")
    reasons.update(candidate["implicitBindingReasons"])
    if limit is not None and selected >= limit:
        reasons.add("bounded pilot selection limit")
    if sampling_reason is not None:
        reasons.add(sampling_reason)
    return sorted(reasons)
