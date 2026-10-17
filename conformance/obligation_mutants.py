"""The admission obligations, and the evidence for each obligation conjunct.

The verification target admits a write only when `LiteralData.insertReady` or
`LiteralData.updateReady` holds, through `statementReady` (`StatementStep.lean`). Each
conjunct either keeps a state out of the model that the model would describe wrongly,
or repeats a guarantee made elsewhere. `OBLIGATIONS` lists the conjuncts. A conjunct
that a native state could violate after resolution would need a mutant that removes it
and a boundary case that disagrees with native SQLite without it. Since slice 5a
(ADR 0012, amendment 4) no conjunct is of that kind: the key conjuncts that required
integer or NULL key cells left with SQLite's key equality, so `MUTANTS` is empty and
every conjunct names in `COVERED_ELSEWHERE` what keeps such states out before the
obligation is checked.
`statementReady` admits every DELETE: DELETE compares no key values and cannot fail a
constraint, and its filter has SQLite's comparison rules, so it adds no conjunct.
"""

from conformance.resolve_mutants import SQLITE

LITERAL_DATA = SQLITE + "LiteralData.lean"
"""The admission obligations of literal writes."""
EXECUTION = SQLITE + "StatementStep.lean"
"""The admission obligation of each statement."""
ROW_UPDATE = SQLITE + "RowUpdate.lean"
"""The admission obligation of UPDATE."""

OBLIGATIONS: dict[str, tuple[str, str, str]] = {
    "insert-table-ready": (LITERAL_DATA, "insertReady", "tableReady keys table"),
    "insert-alias-ready": (LITERAL_DATA, "insertReady", "aliasReady table.shape"),
    "insert-row-width": (LITERAL_DATA, "insertReady", "values.length == table.shape.columns.length"),
    "insert-stored-form": (LITERAL_DATA, "insertReady",
                        "(table.shape.columns.zip values).all (fun (column, value) => storedForm column.affinity value)"),
    "insert-rowid-bounded": (LITERAL_DATA, "insertReady",
                             "(inserted table rows).rows.all (fun row => boundedInteger row.rowid)"),
    "update-table-ready": (ROW_UPDATE, "updateReady", "tableReady keys table"),
    "update-alias-ready": (ROW_UPDATE, "updateReady", "aliasReady table.shape"),
    "update-assigned-column": (ROW_UPDATE, "updateReady", "(table.shape.columns[position]?).isSome"),
    "update-rowid-bounded": (ROW_UPDATE, "updateReady",
                             "(updated table assignments filter).rows.all (fun row => boundedInteger row.rowid)"),
    "create-table-plain": (EXECUTION, "statementReady", "table.plain"),
    "add-column-default-readback": (EXECUTION, "statementReady", "(readDefaultValue column).toOption.isSome"),
    "create-index-refused": (EXECUTION, "statementReady", "| .createIndex .. => false"),
}
"""Each conjunct of the admission obligations: the file under `packages/`, the declaration
that contains it, and its exact text there."""

COVERED_ELSEWHERE: dict[str, str] = {
    "insert-alias-ready": "reason:SQLite makes a column a rowid alias only when its declared type is INTEGER, "
                          "which has INTEGER affinity (aliasesRowid), so every native table passes",
    "update-alias-ready": "reason:SQLite makes a column a rowid alias only when its declared type is INTEGER, "
                          "which has INTEGER affinity (aliasesRowid), so every native table passes",
    "update-rowid-bounded": "reason:an alias holds a 64-bit integer in every native state, and a SET value for the "
                            "alias is a constant that SQLite's integers bound; a larger value is a REAL and a "
                            "datatype mismatch",
    "insert-row-width": "reason:resolution gives one value per column (RowSpec.fullRow_rowWidth)",
    "insert-stored-form": "reason:resolution stores every written value with storeValue, which is idempotent "
                          "(StoreValueLaws.storeValue_storeValue)",
    "insert-table-ready": "reason:SQLite keeps the NOT NULL cells and unique keys of every table that it stores, "
                          "so every native state passes tableReady",
    "insert-rowid-bounded": "reason:after the largest rowid SQLite chooses a random rowid, so a native "
                            "record of the boundary cannot be replayed exactly",
    "update-assigned-column": "reason:resolution gives each assignment the position of a column of the table "
                              "(Updates.resolveAssignment)",
    "update-table-ready": "reason:SQLite keeps the NOT NULL cells and unique keys of every table that it stores, "
                          "so every native state passes tableReady",
    "create-table-plain": "restriction:create-table-constraints",
    "add-column-default-readback": "restriction:add-column-constraint",
    "create-index-refused": "restriction:create-index-runs",
}
"""For each conjunct without a mutant: `restriction:ID`, the restriction that resolution
reports before the obligation is checked, or `reason:` and why no boundary case exists."""

MUTANTS: dict[str, tuple[str, str, str]] = {}
"""The mutants that each remove one conjunct of `OBLIGATIONS` and make its boundary case
disagree; none since slice 5a, as the module documentation explains."""

TARGETS: dict[str, tuple[str, ...]] = {}
"""The boundary case that each mutant changes."""

GUARDS: dict[str, str] = {}
"""The obligation conjunct that each mutant removes. `conformance.mutant_guards` checks every entry."""
