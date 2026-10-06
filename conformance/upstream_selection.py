"""Keep acquisition exclusions independent of corpus size and sampling policy."""

from conformance.case_format import Json
from conformance.query_window import tokens


def implicit_binding_reasons(command: str) -> set[str]:
    """Name untraced Tcl slots without treating comments or quoted text as bindings."""
    return {"implicit Tcl parameter binding: " + token.text for token in tokens(command)
            if len(token.text) > 1 and token.text != "::" and token.text.startswith(("$", ":", "@"))}


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
    if "implicitBindingReasons" in candidate:
        reasons.update(candidate["implicitBindingReasons"])
    else:
        # Older candidates have no trace-time aggregate; preserve their exclusion semantics.
        for command in candidate.get("prefix", []) + candidate["commands"]:
            if isinstance(command, str):
                reasons.update(implicit_binding_reasons(command))
    if limit is not None and selected >= limit:
        reasons.add("bounded pilot selection limit")
    if sampling_reason is not None:
        reasons.add(sampling_reason)
    return sorted(reasons)
