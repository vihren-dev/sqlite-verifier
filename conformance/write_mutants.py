"""Mutants of writes with output (ADR 0012, slice 3a).

The task of slice 3a lists the changes that the conformance suite must notice. Each
mutant is one text change in a copy of the model, which
`conformance.resolve_mutants.measure` builds and runs against its target case of
`conformance.authored_writes`.
"""

OUTPUTS = "belay-sqlite-model/Belay/Sqlite/Model/StatementOutput.lean"
"""The outputs of statements, with the RETURNING rows."""
RETURNING = "belay-sqlite-model/Belay/Sqlite/Model/Resolution/Returning.lean"
"""The resolution of RETURNING columns."""
CELLS = "belay-sqlite-model/Belay/Sqlite/Model/Resolution/InsertCells.lean"
"""The constant values of INSERT rows."""

MUTANTS: dict[str, tuple[str, str, str]] = {
    "update_returning_old_values": (OUTPUTS,
        "let written := chosen.map fun row => (LiteralData.assign context table.shape.columns assignments row).values",
        "let written := chosen.map fun row => row.values"),
    "update_returning_every_row": (OUTPUTS,
        "      let written := chosen.map fun row =>", "      let written := table.rows.map fun row =>"),
    "returning_rows_on_failure": (OUTPUTS,
        "      let written := ((LiteralData.inserted table values).rows.drop table.rows.length).map (·.values)\n"
        "      return ⟨names, returnedRows context returning written, some (run.counts.changes.getD 0)⟩\n"
        "    else if constraintFailure then some ⟨names, [], some (run.counts.changes.getD 0)⟩ else none",
        "      let written := ((LiteralData.inserted table values).rows.drop table.rows.length).map (·.values)\n"
        "      return ⟨names, returnedRows context returning written, some (run.counts.changes.getD 0)⟩\n"
        "    else if constraintFailure then\n"
        "      some ⟨names, returnedRows context returning (Resolved.rowsAt context [] rows),\n"
        "        some (run.counts.changes.getD 0)⟩ else none"),
    "returning_names_ignore_definition": (RETURNING,
        "      .ok [(resolved, (alias.map (·.text)).getD ((definedName scope value).getD text))]",
        "      .ok [(resolved, (alias.map (·.text)).getD text)]"),
    "constant_not_evaluated": (CELLS,
        "    else .ok (.value (operand.1.eval (.plain 0) []))",
        "    else .ok (.value (match operand.1 with\n"
        "      | .arithmetic _ left _ => left.eval (.plain 0) []\n      | other => other.eval (.plain 0) []))"),
}
"""Each mutant: the file under `packages/`, the exact text it changes, and the
replacement. The names follow the list in the task of slice 3a; `constant_not_evaluated`
stores the left operand of an arithmetic constant, so `1 + 2` would be stored as 1."""

TARGETS: dict[str, tuple[str, ...]] = {
    "update_returning_old_values": ("update-returning-new-values",),
    "update_returning_every_row": ("update-returning-new-values",),
    "returning_rows_on_failure": ("returning-not-null-failure",),
    "returning_names_ignore_definition": ("returning-defined-names",),
    "constant_not_evaluated": ("insert-constant-expressions",),
}
"""The authored case of `conformance.authored_writes` that each mutant changes."""

GUARDS: dict[str, str] = {
    "update_returning_old_values": "rule:statementOutput",
    "update_returning_every_row": "rule:statementOutput",
    "returning_rows_on_failure": "rule:statementOutput",
    "returning_names_ignore_definition": "rule:returningColumn",
    "constant_not_evaluated": "rule:constantCell",
}
"""What each mutant guards: `rule:` and the Lean declaration of its file that the mutant
changes. `conformance.mutant_guards` checks every entry."""
