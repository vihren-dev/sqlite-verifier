"""Mutants of writes with output (ADR 0012, slice 3a).

The task of slice 3a lists the changes that the conformance suite must notice. Each
mutant is one text change in a copy of the model, which
`conformance.resolve_mutants.measure` builds and runs against its target case of
`conformance.authored_writes`.
"""

OUTPUTS = "verifier-conformance/VerifierConformance/Outputs.lean"
"""The outputs of statements, with the RETURNING rows."""
RETURNING = "belay-sqlite/Belay/Sqlite/Resolution/Returning.lean"
"""The resolution of RETURNING columns."""
EXPRESSIONS = "belay-sqlite/Belay/Sqlite/Resolution/QueryExprs.lean"
"""The constant values of writes."""

MUTANTS: dict[str, tuple[str, str, str]] = {
    "update_returning_old_values": (OUTPUTS,
        "let written := chosen.map fun row => (LiteralData.assign table.shape.columns assignments row).values",
        "let written := chosen.map fun row => row.values"),
    "update_returning_every_row": (OUTPUTS,
        "      let written := chosen.map fun row =>", "      let written := table.rows.map fun row =>"),
    "returning_rows_on_failure": (OUTPUTS,
        "      return ⟨names, returnedRows returning written, some rows.length⟩\n"
        "    else if constraintFailure then some ⟨names, [], some 0⟩ else none",
        "      return ⟨names, returnedRows returning written, some rows.length⟩\n"
        "    else if constraintFailure then some ⟨names, returnedRows returning rows, some 0⟩ else none"),
    "returning_names_ignore_definition": (RETURNING,
        "      .ok [(resolved, alias.getD ((definedName scope value).getD text))]", "      .ok [(resolved, alias.getD text)]"),
    "constant_not_evaluated": (EXPRESSIONS,
        "else .ok (operand.1.eval [])",
        "else .ok (match operand.1 with\n"
        "    | .arithmetic _ left _ => left.eval []\n    | other => other.eval [])"),
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
    "constant_not_evaluated": "rule:constantValue",
}
"""What each mutant guards: `rule:` and the Lean declaration of its file that the mutant
changes. `conformance.mutant_guards` checks every entry."""
