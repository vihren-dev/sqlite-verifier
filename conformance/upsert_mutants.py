"""Mutants of UPSERT (ADR 0012, amendment 4, slice 5c).

The task of slice 5c lists the changes that the conformance suite must notice. Each
mutant is one text change in a copy of the model, which
`conformance.resolve_mutants.measure` builds and runs against its target case of
`conformance.authored_upserts`.
"""

from conformance.resolve_mutants import SQLITE

UPSERT = SQLITE + "Upsert.lean"
"""The ON CONFLICT clauses of INSERT."""
RUN = SQLITE + "UpsertRun.lean"
"""The rows of an INSERT with ON CONFLICT clauses."""
OUTPUTS = "verifier-conformance/VerifierConformance/Outputs.lean"
"""The outputs of statements, with the change count."""

MUTANTS: dict[str, tuple[str, str, str]] = {
    "update_first_row": (RUN,
        "      | .update assignments filter => updateExisting keys table assignments filter existing proposed",
        "      | .update assignments filter => updateExisting keys table assignments filter"
        " (table.rows.headD existing) proposed"),
    "excluded_reads_existing": (UPSERT, "  let context := existing.values ++ proposed.values",
        "  let context := existing.values ++ existing.values"),
    "last_clause_handles": (UPSERT,
        "  clauses.findSome? fun clause => (conflictingRow (clauseKeys keys clause) table proposed).map (clause, ·)",
        "  clauses.reverse.findSome? fun clause => (conflictingRow (clauseKeys keys clause) table proposed).map"
        " (clause, ·)"),
    "target_checks_every_key": (UPSERT, "  | some key => [key]", "  | some _ => keys"),
    "later_row_ignores_earlier": (RUN,
        "    | .ok (next, written) => match upsertRun keys policy clauses next rest with",
        "    | .ok (_, written) => match upsertRun keys policy clauses table rest with"),
    "skipped_row_counted": (OUTPUTS,
        "      return ⟨names, returnedRows returning (written.map (·.values)), some written.length⟩",
        "      return ⟨names, returnedRows returning (written.map (·.values)), some rows.length⟩"),
    "update_not_checked": (UPSERT, "  else checkedRow keys (replaceRow table existing changed) changed",
        "  else .ok (replaceRow table existing changed, some changed)"),
}
"""Each mutant: the file under `packages/`, the exact text it changes, and the
replacement. The names follow the list in the task of slice 5c: DO UPDATE changes the
first row of the table instead of the conflicting row; `excluded` reads the existing row
instead of the proposed row; the last matching clause handles the row; a target checks
every key, so an untargeted key is handled; a later row does not see the rows of earlier
ones; a skipped row is counted in the change count; the row of DO UPDATE is not checked
against the other keys."""

TARGETS: dict[str, tuple[str, ...]] = {
    "update_first_row": ("upsert-targeted-before-untargeted",), "excluded_reads_existing": ("upsert-update-excluded",),
    "last_clause_handles": ("upsert-clause-order",), "target_checks_every_key": ("upsert-untargeted-key",),
    "later_row_ignores_earlier": ("upsert-later-row",), "skipped_row_counted": ("upsert-mixed-rows",),
    "update_not_checked": ("upsert-update-key-conflict",),
}
"""The authored case of `conformance.authored_upserts` that each mutant changes."""

GUARDS: dict[str, str] = {
    "update_first_row": "rule:upsertRow", "excluded_reads_existing": "rule:updateExisting",
    "last_clause_handles": "rule:handlingClause", "target_checks_every_key": "rule:clauseKeys",
    "later_row_ignores_earlier": "rule:upsertRun", "skipped_row_counted": "rule:statementOutput",
    "update_not_checked": "rule:updateExisting",
}
"""What each mutant guards: `rule:` and the Lean declaration of its file that the mutant
changes. `conformance.mutant_guards` checks every entry."""
