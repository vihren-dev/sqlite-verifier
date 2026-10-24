"""Mutants of DELETE (ADR 0012, amendment 1, slice 3c).

The task of slice 3c lists the changes that the conformance suite must notice. Each
mutant is one text change in a copy of the model, which
`conformance.resolve_mutants.measure` builds and runs against its target case of
`conformance.authored_deletes`.
"""

from conformance.resolve_mutants import SQLITE

ROW_DELETE = SQLITE + "RowDelete.lean"
"""The execution of DELETE."""
LITERAL_DATA = SQLITE + "LiteralData.lean"
"""The rowid of an inserted row."""
OUTPUTS = "belay-sqlite-model/Belay/Sqlite/Model/StatementOutput.lean"
"""The outputs of statements, with the RETURNING rows."""
STEP = SQLITE + "StatementStep.lean"
"""The run of a statement, with the counts of its changes."""

MUTANTS: dict[str, tuple[str, str, str]] = {
    "null_filter_deletes": (ROW_DELETE,
        "  { table with rows := table.rows.filter fun row => !selected context filter row }",
        "  { table with rows := table.rows.filter fun row =>\n"
        "      !(filter.all fun condition => !Resolved.falsy (condition.eval context row.values)) }"),
    "delete_keeps_selected_rows": (ROW_DELETE,
        "  { table with rows := table.rows.filter fun row => !selected context filter row }",
        "  { table with rows := table.rows.filter fun row => selected context filter row }"),
    "delete_returning_kept_rows": (OUTPUTS,
        "returnedRows context returning (chosen.map (·.values)), some (run.counts.changes.getD 0)⟩",
        "returnedRows context returning ((table.rows.filter (!LiteralData.selected context filter ·)).map (·.values)),\n"
        "        some (run.counts.changes.getD 0)⟩"),
    "delete_change_count_every_row": (STEP,
        "(LiteralData.changedCounts (.ok database) (table.scanRows.filter (LiteralData.selected context filter)).length)",
        "(LiteralData.changedCounts (.ok database) table.scanRows.length)"),
    "next_rowid_counts_rows": (LITERAL_DATA,
        "  | first :: rest => (rest.foldl (fun largest row => max largest row.rowid) first.rowid) + 1",
        "  | first :: rest => (rest.length : Int) + 2"),
}
"""Each mutant: the file under `packages/`, the exact text it changes, and the
replacement. The names follow the list in the task of slice 3c: a NULL filter deletes
the row; DELETE keeps the selected rows instead of the others; RETURNING returns the
kept rows; the change count counts every row; the next rowid counts the rows instead of
following the largest remaining rowid."""

TARGETS: dict[str, tuple[str, ...]] = {
    "null_filter_deletes": ("delete-null-filter",), "delete_keeps_selected_rows": ("delete-some-rows",),
    "delete_returning_kept_rows": ("delete-returning-old-rows",), "delete_change_count_every_row": ("delete-no-row",),
    "next_rowid_counts_rows": ("delete-then-insert",),
}
"""The authored case of `conformance.authored_deletes` that each mutant changes."""

GUARDS: dict[str, str] = {
    "null_filter_deletes": "rule:deleted", "delete_keeps_selected_rows": "rule:deleted",
    "delete_returning_kept_rows": "rule:statementOutput", "delete_change_count_every_row": "rule:runStatement",
    "next_rowid_counts_rows": "rule:nextRowid",
}
"""What each mutant guards: `rule:` and the Lean declaration of its file that the mutant
changes. `conformance.mutant_guards` checks every entry."""
