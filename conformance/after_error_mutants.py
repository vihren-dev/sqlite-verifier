"""Mutants of the run that continues after an error (task "Evidence for the statements after an
error", Tests).

Each mutant is one text change in a copy of the model, which `conformance.resolve_mutants.measure`
builds and runs against its target case of `conformance.authored_after_error`. They are the risks
that the task names: an error treated as `OR ROLLBACK`, the exception of `OR ROLLBACK` lost, and
resolution that assumes that earlier statements succeed.
"""

RUN = "belay-sqlite-model/Belay/Sqlite/Model/ScriptRun.lean"
"""The model's run of a script, with the connection after each statement."""

MUTANTS: dict[str, tuple[str, str, str]] = {
    "error_closes_the_transaction": (RUN,
        "  | .pending persisted visible _ =>\n"
        "    { state := { connection.state with database := visible, snapshot := some persisted },\n"
        "      foreignKeys := after.foreignKeys, recursiveTriggers := after.recursiveTriggers }",
        "  | .pending persisted _ _ =>\n"
        "    { state := { connection.state with database := persisted, snapshot := none },\n"
        "      foreignKeys := after.foreignKeys, recursiveTriggers := after.recursiveTriggers }"),
    "rollback_keeps_the_transaction": (RUN,
        "  | .success database | .failure _ _ database =>\n"
        "    { state := { connection.state with database, snapshot := none }, foreignKeys := after.foreignKeys,\n"
        "      recursiveTriggers := after.recursiveTriggers }",
        "  | .success database =>\n"
        "    { state := { connection.state with database, snapshot := none }, foreignKeys := after.foreignKeys,\n"
        "      recursiveTriggers := after.recursiveTriggers }\n"
        "  | .failure _ _ database =>\n"
        "    { state := { connection.state with database }, foreignKeys := after.foreignKeys,\n"
        "      recursiveTriggers := after.recursiveTriggers }"),
    "failed_statement_changes_the_catalog": (RUN,
        "      else ran resolved after value (advanceWith index resolved connection.state run.effect)",
        "      else ran resolved after value (match advanceWith index resolved connection.state run.effect with\n"
        "        | .halt (.failure position reason database) =>\n"
        "          .halt (.failure position reason { database with catalog := after.catalog })\n"
        "        | transition => transition)"),
}
"""Each mutant: the file under `packages/`, the exact text it changes, and the replacement.
`error_closes_the_transaction` rolls back and closes an open transaction after every error;
`rollback_keeps_the_transaction` keeps the transaction open after the rollback of `OR ROLLBACK`;
`failed_statement_changes_the_catalog` gives a statement that fails the catalog that resolution
folds for it, so that the next statement resolves as if it had succeeded."""

TARGETS: dict[str, tuple[str, ...]] = {
    "error_closes_the_transaction": ("abort-in-transaction",),
    "rollback_keeps_the_transaction": ("insert-or-rollback-in-transaction",),
    "failed_statement_changes_the_catalog": ("failed-add-column-leaves-no-column",),
}
"""The authored case of `conformance.authored_after_error` that each mutant changes."""

GUARDS: dict[str, str] = {
    "error_closes_the_transaction": "rule:Connection.afterError",
    "rollback_keeps_the_transaction": "rule:Connection.afterError",
    "failed_statement_changes_the_catalog": "rule:runScriptStepWith",
}
"""What each mutant guards: `rule:` and the Lean declaration of its file that the mutant
changes. `conformance.mutant_guards` checks every entry."""
