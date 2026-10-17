"""Mutants of USING and NATURAL joins (ADR 0012, amendment 2, slice 4b).

The task of slice 4b lists the changes that the conformance suite must notice. Each
mutant is one text change in a copy of the model, which
`conformance.resolve_mutants.measure` builds and runs against its target case of
`conformance.authored_using`.
"""

from conformance.resolve_mutants import SQLITE

SCOPE = SQLITE + "Resolution/Scope.lean"
"""The names in scope, with the merged columns."""
MERGED_LEFT = SQLITE + "Resolution/MergedLeft.lean"
"""The left side of the generated condition."""
JOIN_USING = SQLITE + "Resolution/JoinUsing.lean"
"""The merged names and the generated condition of USING and NATURAL joins."""

MUTANTS: dict[str, tuple[str, str, str]] = {
    "star_keeps_merged": (SCOPE,
        "      fun (index, _) => !source.merged.contains index && !source.hidden.contains index).map",
        "      fun (index, _) => !source.hidden.contains index).map"),
    "unqualified_sees_merged": (SCOPE, "      if source.merged.contains index then match source.mergeRule with",
        "      if false then match source.mergeRule with"),
    "condition_uses_right_most": (MERGED_LEFT, "  scope.findSome? fun source =>", "  scope.reverse.findSome? fun source =>"),
    "natural_without_common_no_rows": (JOIN_USING, "  | [] => none\n  | first :: rest => some (rest.foldl .and first)",
        "  | [] => some (.equals (.numeric \"0\") (.numeric \"1\"))\n  | first :: rest => some (rest.foldl .and first)"),
    "missing_using_column_accepted": (JOIN_USING,
        "  if (columnPosition right.columns name).isSome && (left.leftMost name).isSome then\n",
        "  if true then\n"),
    "natural_with_on_accepted": (JOIN_USING,
        "    if join.condition.isSome || join.usingColumns.isSome then .error (.prepare .naturalJoinCondition)",
        "    if false then .error (.prepare .naturalJoinCondition)"),
}
"""Each mutant: the file under `packages/`, the exact text it changes, and the
replacement. The names follow the list in the task of slice 4b: `*` keeps the merged
right column; an unqualified merged name still sees the right column, which makes it
ambiguous; the condition uses the right-most instead of the left-most left column;
NATURAL without a common column gives no rows instead of a cross join; a USING name
that is not in both inputs is accepted; NATURAL with ON is accepted."""

TARGETS: dict[str, tuple[str, ...]] = {
    "star_keeps_merged": ("using-inner",), "unqualified_sees_merged": ("using-left-merged-names",),
    "condition_uses_right_most": ("natural-left-most",), "natural_without_common_no_rows": ("natural-no-common",),
    "missing_using_column_accepted": ("using-missing-column",), "natural_with_on_accepted": ("natural-with-on",),
}
"""The authored case of `conformance.authored_using` that each mutant changes."""

GUARDS: dict[str, str] = {
    "star_keeps_merged": "rule:Scope.visible", "unqualified_sees_merged": "rule:Scope.resolveStep",
    "condition_uses_right_most": "rule:Scope.leftMost", "natural_without_common_no_rows": "rule:mergedCondition",
    "missing_using_column_accepted": "rule:usingNameChecked", "natural_with_on_accepted": "rule:mergedNames",
}
"""What each mutant guards: `rule:` and the Lean declaration of its file that the mutant
changes. `conformance.mutant_guards` checks every entry."""
