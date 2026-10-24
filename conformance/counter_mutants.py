"""Mutants of the counts of the connection counters (ADR 0024, slice 1, Tests).

Each mutant is one text change in a copy of the model, which `conformance.resolve_mutants.measure`
builds and runs against its target case of `conformance.authored_counters`. They are the risks that
the task names: the rows that REPLACE deletes counted, the rows of trigger programs counted in
`changes()` or left out of `total_changes()`, a `DROP TABLE` of a referenced table that does not set
`changes()`, `changes()` kept after a failure, `last_insert_rowid()` taken back by the rollback, and
the changes of programs and actions before a failure left out of `total_changes()`.
"""

MODEL = "belay-sqlite-model/Belay/Sqlite/Model/"
"""The folder of the model's sources, under `packages/`."""

MUTANTS: dict[str, tuple[str, str, str]] = {
    "replace_deletes_are_counted": (MODEL + "RowInsert.lean",
        "KeyResult.mapState (fun deleted => { deleted with own := state.own })",
        "KeyResult.mapState (fun deleted => deleted)"),
    "program_rows_count_in_changes": (MODEL + "ForeignKeyWrites.lean",
        "{ changes := some state.own, total := state.own + state.credited, lastRowid := state.inserted }",
        "{ changes := some (state.own + state.credited), total := state.own + state.credited, lastRowid := state.inserted }"),
    "program_rows_are_not_in_total_changes": (MODEL + "RowCredit.lean",
        "  | .ok reached => .ok { restore reached with credited := reached.credited + reached.own }",
        "  | .ok reached => .ok { restore reached with credited := reached.credited }"),
    "drop_table_leaves_changes": (MODEL + "ForeignKeyWrites.lean",
        "    | .ok after => { run with effect := .ok (after.drop positions) }",
        "    | .ok after => { run with effect := .ok (after.drop positions), counts := { run.counts with changes := none } }"),
    "changes_kept_after_a_failure": (MODEL + "PlainCounts.lean",
        "  | .error _ => { changes := some 0, lastRowid := stored (insertedBefore keys table rows) }",
        "  | .error _ => { lastRowid := stored (insertedBefore keys table rows) }"),
    "rollback_takes_back_the_last_rowid": (MODEL + "SqlAdvance.lean",
        "    | some original => .next { state with database := original, snapshot := none }",
        "    | some original => .next { state with database := original, snapshot := none, "
        "counters := { state.counters with lastInsertRowid := some 0 } }"),
    "failure_loses_the_rows_of_programs": (MODEL + "ForeignKeyWrites.lean",
        "{ changes := some 0, total := state.credited, lastRowid := state.inserted }",
        "{ changes := some 0, total := 0, lastRowid := state.inserted }"),
}
"""Each mutant: the file under `packages/`, the exact text it changes, and the replacement.
`replace_deletes_are_counted` counts the row that REPLACE deletes as a row of the statement;
`program_rows_count_in_changes` adds the rows of trigger programs and foreign-key actions to
`changes()`; `program_rows_are_not_in_total_changes` leaves them out of `total_changes()`;
`drop_table_leaves_changes` gives the `DROP TABLE` of a referenced table no `changes()` value;
`changes_kept_after_a_failure` does not set `changes()` to 0 when an INSERT fails;
`rollback_takes_back_the_last_rowid` resets `last_insert_rowid()` at ROLLBACK; and
`failure_loses_the_rows_of_programs` leaves the rows of completed programs out of `total_changes()`
when a write fails."""

TARGETS: dict[str, tuple[str, ...]] = {
    "replace_deletes_are_counted": ("insert-or-replace-with-foreign-keys",),
    "program_rows_count_in_changes": ("trigger-programs-count",),
    "program_rows_are_not_in_total_changes": ("trigger-programs-count", "foreign-key-actions-count"),
    "drop_table_leaves_changes": ("drop-table-with-foreign-key-actions",),
    "changes_kept_after_a_failure": ("failed-insert-keeps-the-rowid",),
    "rollback_takes_back_the_last_rowid": ("rollback-keeps-the-counters",),
    "failure_loses_the_rows_of_programs": ("failed-write-after-trigger-rows",),
}
"""The authored cases of `conformance.authored_counters` that each mutant changes."""

GUARDS: dict[str, str] = {
    "replace_deletes_are_counted": "rule:replaceDelete",
    "program_rows_count_in_changes": "rule:KeyState.keptCounts",
    "program_rows_are_not_in_total_changes": "rule:NestedRun.credited",
    "drop_table_leaves_changes": "rule:dropKeys",
    "changes_kept_after_a_failure": "rule:insertCounts",
    "rollback_takes_back_the_last_rowid": "rule:advanceWith",
    "failure_loses_the_rows_of_programs": "rule:KeyState.failedCounts",
}
"""What each mutant guards: `rule:` and the Lean declaration of its file that the mutant changes.
`conformance.mutant_guards` checks every entry."""
