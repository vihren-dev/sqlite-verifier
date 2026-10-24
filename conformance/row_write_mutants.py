"""Mutants of row-dependent writes (ADR 0012, amendment 1, "Testing").

The amendment lists the changes that the conformance suite must notice. Each mutant is
one text change in a copy of the model, which `conformance.resolve_mutants.measure`
builds and runs against its target case of `conformance.authored_row_writes`.
"""

from conformance.resolve_mutants import SQLITE

ROW_UPDATE = SQLITE + "RowUpdate.lean"
"""The execution of UPDATE."""
STORE = SQLITE + "StoreValue.lean"
"""Store-time affinity."""
ROWS = SQLITE + "Resolution/InsertCells.lean"
"""The rows of INSERT, which store each value."""
UPDATES = SQLITE + "Resolution/Updates.lean"
"""The resolution of UPDATE, which stores each constant value."""
EXECUTION = SQLITE + "StatementStep.lean"
"""The checked write of INSERT and UPDATE."""

MUTANTS: dict[str, tuple[str, str, str]] = {
    "set_reads_new_row": (ROW_UPDATE,
        "values.set position (Value.store (positionAffinity columns position) (expression.eval context cells))) row.values) }",
        "values.set position (Value.store (positionAffinity columns position) (expression.eval context values))) row.values) }"),
    "null_filter_selects": (ROW_UPDATE,
        "  filter.all fun condition => Resolved.truthy (condition.eval context row.values)",
        "  filter.all fun condition => !Resolved.falsy (condition.eval context row.values)"),
    "no_store_affinity": (ROW_UPDATE,
        "values.set position (Value.store (positionAffinity columns position) (expression.eval context cells))) row.values) }",
        "values.set position (expression.eval context cells)) row.values) }"),
    "cast_as_store_affinity": (ROWS,
        "  | .value written => .value (Value.store affinity written)",
        "  | .value written => .value (castValue affinity written)"),
    "real_column_keeps_integer": (STORE,
        "  | .integer whole => .real (positiveZero (Float.ofInt whole).toBits)", "  | .integer whole => .integer whole"),
    "text_column_keeps_number": (STORE,
        "  | .text, .integer _ | .text, .real _ => .text value.textBytes", "  | .text, .integer _ | .text, .real _ => value"),
    "change_count_every_row": (EXECUTION,
        "(LiteralData.changedCounts effect (table.scanRows.filter (LiteralData.selected context filter)).length)",
        "(LiteralData.changedCounts effect table.scanRows.length)"),
}
"""Each mutant: the file under `packages/`, the exact text it changes, and the
replacement. The names follow the list of the amendment: SET values read the new row; a
NULL filter selects the row; no store affinity at execution; `castValue`
as store affinity; a REAL column keeps an integer; a TEXT column keeps a number; the
change count counts every row. A failed UPDATE that keeps the rows it changed is the
algorithms mutant `failure_keeps_rows`, since one publication path decides what every
failure keeps (ADR 0013, D8). The execution
stores every assigned value again, so a constant that resolution does not store differs
in no observable way since slice 5a removed the key-domain check, and that change has no
mutant."""

TARGETS: dict[str, tuple[str, ...]] = {
    "set_reads_new_row": ("update-swap",), "null_filter_selects": ("update-null-filter",),
    "no_store_affinity": ("update-stores-row-value",),
    "cast_as_store_affinity": ("store-other-text",), "real_column_keeps_integer": ("store-integer-into-real",),
    "text_column_keeps_number": ("store-whole-real",),
    "change_count_every_row": ("update-no-match",),
}
"""The authored case of `conformance.authored_row_writes` that each mutant changes."""

GUARDS: dict[str, str] = {
    "set_reads_new_row": "rule:assignFrom", "null_filter_selects": "rule:selected",
    "no_store_affinity": "rule:assignFrom",
    "cast_as_store_affinity": "rule:Resolved.Cell.stored", "real_column_keeps_integer": "rule:realRead",
    "text_column_keeps_number": "rule:Value.store",
    "change_count_every_row": "rule:runStatement",
}
"""What each mutant guards: `rule:` and the Lean declaration of its file that the mutant
changes. `conformance.mutant_guards` checks every entry."""
