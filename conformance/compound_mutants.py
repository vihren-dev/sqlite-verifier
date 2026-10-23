"""Mutants of compound SELECT (ADR 0019, slice 3; plans/20261023-compound-select.task.md).

The task lists the changes that the conformance suite must notice. Each mutant is one text change
in a copy of the model, which `conformance.resolve_mutants.measure` builds and runs against its
target case of `conformance.authored_compound`.
"""

from conformance.resolve_mutants import SQLITE

ROWS = SQLITE + "CompoundRows.lean"
"""The duplicate rule and the rows of each operator of a compound."""
RUN = SQLITE + "CompoundRun.lean"
"""The end of the run of a compound: the terms that SQLite runs and where it reads the window."""
TERMS = SQLITE + "Resolution/CompoundTerms.lean"
"""The collations of the columns of a compound from the collations of its terms."""
ORDER = SQLITE + "Resolution/CompoundOrderBy.lean"
"""The terms of the ORDER BY of a compound, with their collations."""
RESOLUTION = SQLITE + "Resolution/CompoundResolution.lean"
"""The resolution of a compound query: its column collations, and the shape that IN and a scalar
subquery read."""

MUTANTS: dict[str, tuple[str, str, str]] = {
    "compound_right_to_left": (ROWS,
        "  compound.rest.foldl (fun (rows, certain) (operator, index) =>\n"
        "      let right := (context.subqueries index outer).rows\n"
        "      (operator.combine compound.collations rows right, certain && operator.keepsCertain compound.collations rows right))\n"
        "    ((context.subqueries compound.first outer).rows, true)\n",
        "  let lefts := compound.first :: compound.rest.map (·.2)\n"
        "  let last := (compound.rest.getLast?.map (·.2)).getD compound.first\n"
        "  ((compound.rest.map (·.1)).zip lefts).foldr (fun (operator, index) (rows, certain) =>\n"
        "      let left := (context.subqueries index outer).rows\n"
        "      (operator.combine compound.collations left rows, certain && operator.keepsCertain compound.collations left rows))\n"
        "    ((context.subqueries last outer).rows, true)\n"),
    "except_keeps_duplicates": (ROWS,
        "  | .except, left, right => (distinctRows collations left).filter fun row => !right.any (sameOutput collations row)",
        "  | .except, left, right => left.filter fun row => !right.any (sameOutput collations row)"),
    "null_unequal_null": (ROWS,
        "    collation.compare a b == .eq\n",
        "    collation.compare a b == .eq && !a.isNull\n"),
    "collation_right_most": (TERMS,
        "  (List.range width).map fun column => (terms.findSome? fun term => term.getD column none).getD .binary\n",
        "  (List.range width).map fun column => (terms.reverse.findSome? fun term => term.getD column none).getD .binary\n"),
    "collation_binary": (RESOLUTION,
        "  let collations := compoundCollations (terms.map fun term => optionalCollations term.scope term.written.columns) width\n",
        "  let collations := (List.range width).map fun _ => Collation.binary\n"),
    "in_compound_collation": (RESOLUTION,
        "      explicitCollation := last.shape.explicitCollation, columnCollation := last.shape.columnCollation,\n",
        "      explicitCollation := none, columnCollation := collations.head?,\n"),
    "except_runs_right_on_empty": (RUN,
        "    | .except | .intersect => if left.isEmpty then .done else right.ending.intoTable\n",
        "    | .except => right.ending.intoTable\n"
        "    | .intersect => if left.isEmpty then .done else right.ending.intoTable\n"),
    "order_by_binary": (ORDER,
        "      collation := term.expression.outerCollation.getD ((if derived then leftmost else columns).getD column .binary) })\n",
        "      collation := term.expression.outerCollation.getD .binary })\n"),
}
"""Each mutant: the file under `packages/`, the exact text it changes, and the replacement.
The names follow the list of the task: operators that group from the right; `EXCEPT` that keeps
the duplicates of its left rows; NULL unequal to NULL in the duplicate rule; the compound
collation from the right-most term, or always `BINARY`; `IN` with the compound collation instead
of that of the right-most term; the right term of `EXCEPT` run when the left rows are empty; and
an `ORDER BY` term sorted under `BINARY` instead of the compound collation."""

TARGETS: dict[str, tuple[str, ...]] = {
    "compound_right_to_left": ("compound-chains",),
    "except_keeps_duplicates": ("compound-nulls",),
    "null_unequal_null": ("compound-intersect",),
    "collation_right_most": ("compound-except",),
    "collation_binary": ("compound-collation-column",),
    "in_compound_collation": ("compound-in-right-most-term",),
    "except_runs_right_on_empty": ("compound-right-term-skipped",),
    "order_by_binary": ("compound-order-by-collation",),
}
"""The authored case of `conformance.authored_compound` that each mutant changes."""

GUARDS: dict[str, str] = {
    "compound_right_to_left": "rule:Compound.combined",
    "except_keeps_duplicates": "rule:_root_.Belay.Sqlite.Model.CompoundOperator.combine",
    "null_unequal_null": "rule:sameOutput",
    "collation_right_most": "rule:compoundCollations",
    "collation_binary": "rule:resolveCompoundBody",
    "in_compound_collation": "rule:resolveCompoundBody",
    "except_runs_right_on_empty": "rule:stepEnd",
    "order_by_binary": "rule:resolveCompoundOrderBy",
}
"""What each mutant guards: `rule:` and the Lean declaration of its file that the mutant
changes. `conformance.mutant_guards` checks every entry."""
