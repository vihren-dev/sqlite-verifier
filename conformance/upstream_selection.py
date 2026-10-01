"""Keep acquisition exclusions independent of corpus size and sampling policy."""

from conformance.case_format import Json
from conformance.query_window import tokens


def candidate_reasons(candidate: dict[str, Json], *, selected: int, limit: int) -> list[str]:
    """Report all known barriers; a selection limit never hides a fidelity failure."""
    reasons = set(candidate["exclusions"])
    if candidate["failed"]:
        reasons.add("upstream Tcl expectation failed")
    if not candidate["commands"]:
        reasons.add("no SQL observation")
    if any(candidate["codes"][:-1]):
        reasons.add("assertion continues after a SQL error")
    # Tcl binds named SQL variables from its scope; their values/types are not traced.
    for command in candidate.get("prefix", []) + candidate["commands"]:
        if isinstance(command, str):
            reasons.update("implicit Tcl parameter binding: " + token.text for token in tokens(command)
                           if len(token.text) > 1 and token.text != "::" and token.text.startswith(("$", ":", "@")))
    if selected >= limit:
        reasons.add("bounded pilot selection limit")
    return sorted(reasons)
