"""Mutants of RIGHT and FULL joins (ADR 0012, amendment 3, slice 4c).

Amendment 3, "Testing", lists the changes that the conformance suite must notice. Each
mutant is one text change in a copy of the model, which
`conformance.resolve_mutants.measure` builds and runs against its target case of
`conformance.authored_right`.
"""

from conformance.resolve_mutants import SQLITE

QUERY_JOINS = SQLITE + "QueryJoins.lean"
"""The rows of joins."""

ADDED = ("    | .right | .full => (unmatchedRight context left join candidates).map\n"
         "        ((outer ++ List.replicate (leftWidth - outer.length) .null) ++ ·)\n")
"""The added rows of a right or full join."""

MUTANTS: dict[str, tuple[str, str, str]] = {
    "right_drops_unmatched": (QUERY_JOINS, ADDED + "    | .inner | .left => []",
        ADDED.replace("| .right | .full =>", "| .full =>") + "    | .right | .inner | .left => []"),
    "right_pads_own_width": (QUERY_JOINS, ADDED, ADDED.replace("(leftWidth - outer.length)", "width")),
    "unmatched_per_left_row": (QUERY_JOINS,
        "  candidates.filter fun cells => !left.any fun row => join.matches context (row ++ cells)",
        "  candidates.filter fun cells => !left.all fun row => join.matches context (row ++ cells)"),
    "full_omits_unmatched_left": (QUERY_JOINS,
        "  | .inner | .right => joinMatches context row join candidates\n  | .left | .full =>",
        "  | .inner | .right | .full => joinMatches context row join candidates\n  | .left =>"),
}
"""Each mutant: the file under `packages/`, the exact text it changes, and the
replacement. The names follow Amendment 3, "Testing": a right join drops the unmatched
right rows; it pads them with the right table's width instead of the left input's; a
right row counts as unmatched when some left row does not match it, instead of when no
left row matches it; a full join omits the unmatched left rows."""

TARGETS: dict[str, tuple[str, ...]] = {
    "right_drops_unmatched": ("right-on",), "right_pads_own_width": ("right-after-inner",),
    "unmatched_per_left_row": ("right-on",), "full_omits_unmatched_left": ("full-on",),
}
"""The authored case of `conformance.authored_right` that each mutant changes."""

GUARDS: dict[str, str] = {
    "right_drops_unmatched": "rule:joinRows", "right_pads_own_width": "rule:joinRows",
    "unmatched_per_left_row": "rule:unmatchedRight", "full_omits_unmatched_left": "rule:joinRow",
}
"""What each mutant guards: `rule:` and the Lean declaration of its file that the mutant
changes. `conformance.mutant_guards` checks every entry."""
