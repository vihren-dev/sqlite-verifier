"""Mutants of the admission obligations, and the evidence for each obligation conjunct.

The verification target admits a write only when `LiteralData.insertReady` or
`LiteralData.updateReady` holds, through `statementReady` (`SqlExecution.lean`). Each
conjunct either keeps a state out of the model that the model would describe wrongly,
or repeats a guarantee made elsewhere. `OBLIGATIONS` lists the conjuncts. A conjunct
that a native state can violate after resolution has a mutant that removes it and a
boundary case of `conformance.authored_obligations`: with the conjunct the case is
`MODEL_UNSUPPORTED`, without it the case disagrees with native SQLite. Every other
conjunct names in `COVERED_ELSEWHERE` what keeps such states out before the obligation
is checked. The mutants run in the scheduled suite (owner decision of 2026-10-14).
`statementReady` admits every DELETE: DELETE compares no key values and cannot fail a
constraint, and its filter has SQLite's comparison rules, so it adds no conjunct.
"""

from conformance.resolve_mutants import SQLITE

LITERAL_DATA = SQLITE + "LiteralData.lean"
"""The admission obligations of literal writes."""
EXECUTION = SQLITE + "SqlExecution.lean"
"""The admission obligation of each statement."""
ROW_UPDATE = SQLITE + "RowUpdate.lean"
"""The admission obligation of UPDATE."""

OBLIGATIONS: dict[str, tuple[str, str, str]] = {
    "insert-table-ready": (LITERAL_DATA, "insertReady", "tableReady keys table"),
    "insert-row-width": (LITERAL_DATA, "insertReady", "values.length == table.shape.columns.length"),
    "insert-stored-form": (LITERAL_DATA, "insertReady",
                        "(table.shape.columns.zip values).all (fun (column, value) => storedForm column.affinity value)"),
    "insert-key-values": (LITERAL_DATA, "insertReady",
                          "keys.all (·.all fun position => (values[position]?).any integerOrNull)"),
    "insert-rowid-bounded": (LITERAL_DATA, "insertReady",
                             "(inserted table rows).rows.all (fun row => boundedInteger row.rowid)"),
    "update-table-ready": (ROW_UPDATE, "updateReady", "tableReady keys table"),
    "update-assigned-column": (ROW_UPDATE, "updateReady", "(table.shape.columns[position]?).isSome"),
    "update-keys-after": (ROW_UPDATE, "updateReady",
                          "keys.all (·.all (comparisonReady (updated table assignments filter)))"),
    "create-table-plain": (EXECUTION, "statementReady", "table.plain"),
    "add-column-default-readback": (EXECUTION, "statementReady", "(readDefaultValue column).toOption.isSome"),
    "create-index-refused": (EXECUTION, "statementReady", "| .createIndex .. => false"),
}
"""Each conjunct of the admission obligations: the file under `packages/`, the declaration
that contains it, and its exact text there."""

COVERED_ELSEWHERE: dict[str, str] = {
    "insert-row-width": "reason:resolution gives one value per column (RowSpec.fullRow_rowWidth)",
    "insert-stored-form": "reason:resolution stores every written value with storeValue, which is idempotent "
                          "(StoreValueLaws.storeValue_storeValue)",
    "insert-key-values": "restriction:key-value",
    "insert-rowid-bounded": "reason:after the largest rowid SQLite chooses a random rowid, so a native "
                            "record of the boundary cannot be replayed exactly",
    "update-assigned-column": "reason:resolution gives each assignment the position of a column of the table "
                              "(Updates.resolveAssignment)",
    "update-table-ready": "reason:overlaps update-keys-after, which checks every key cell after the update, "
                          "and SQLite guarantees the constraints; update_without_key_checks removes both",
    "create-table-plain": "restriction:create-table-constraints",
    "add-column-default-readback": "restriction:add-column-constraint",
    "create-index-refused": "restriction:create-index-runs",
}
"""For each conjunct without a mutant: `restriction:ID`, the restriction that resolution
reports before the obligation is checked, or `reason:` and why no boundary case exists."""

MUTANTS: dict[str, tuple[str, str, str]] = {
    "insert_without_table_ready": (LITERAL_DATA, "  tableReady keys table &&\n  rows.all", "  rows.all"),
    "update_without_key_checks": (ROW_UPDATE,
        "  tableReady keys table &&\n  assignments.all (fun (position, _) => (table.shape.columns[position]?).isSome) &&\n"
        "  keys.all (·.all (comparisonReady (updated table assignments filter)))",
        "  assignments.all (fun (position, _) => (table.shape.columns[position]?).isSome)"),
}
"""Each mutant: the file under `packages/`, the exact text it changes, and the replacement,
which removes the conjunct that its guard names. Each of the two key checks of
`updateReady` covers the cells that the other checks, so `update_without_key_checks`
removes both."""

TARGETS: dict[str, tuple[str, ...]] = {
    "insert_without_table_ready": ("insert-key-real-equals-integer",),
    "update_without_key_checks": ("update-key-real-equals-integer",),
}
"""The boundary case of `conformance.authored_obligations` that each mutant changes."""

GUARDS: dict[str, str] = {
    "insert_without_table_ready": "obligation:insert-table-ready",
    "update_without_key_checks": "obligation:update-keys-after",
}
"""The obligation conjunct that each mutant removes. `conformance.mutant_guards` checks every entry."""
