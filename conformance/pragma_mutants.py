"""Mutants of pragmas as statements (ADR 0019, slice 2; plans/20261023-pragmas.task.md).

The task lists the changes that the conformance suite must notice. Each mutant is one text change
in a copy of the model, which `conformance.resolve_mutants.measure` builds and runs against its
target cases of `conformance.authored_pragmas`.
"""

from conformance.resolve_mutants import SQLITE

KEY_CHECK = SQLITE + "ForeignKeyCheck.lean"
"""The rows of `PRAGMA foreign_key_check` for one table."""
SATISFIED = SQLITE + "ForeignKeySatisfied.lean"
"""Whether a child row has the parent row that its foreign key requires."""
PRAGMA_ROWS = SQLITE + "Resolution/PragmaRows.lean"
"""The rows of `PRAGMA table_info` and `PRAGMA foreign_key_list`."""
INSERT = SQLITE + "RowInsert.lean"
"""The insert of one row, with the rows that REPLACE deletes."""

MUTANTS: dict[str, tuple[str, str, str]] = {
    "fkid_declaration_order": (KEY_CHECK,
        "  let links := (childLinks database.catalog.foreignKeyLinks position).zipIdx",
        "  let links := (childLinks database.catalog.foreignKeyLinks position).reverse.zipIdx"),
    "missing_parent_skipped": (SATISFIED,
        "    | .mismatch _ | .missing => false",
        "    | .mismatch _ => false\n    | .missing => true"),
    "cid_counts_generated": (PRAGMA_ROWS,
        "  stored.zipIdx.map fun ((column, position), cid) => tableInfoRow table cid position column",
        "  stored.map fun (column, position) => tableInfoRow table position position column"),
    "replace_delete_fires_nothing": (INSERT,
        "target false false frame.recursive state row.rowid)",
        "target false false false state row.rowid)"),
}
"""Each mutant: the file under `packages/`, the exact text it changes, and the replacement.
The names follow the list of the task: `fkid` in declaration order, `foreign_key_check` that
skips a missing parent table, `table_info` with the `cid` of every column, and REPLACE deletes
that fire no trigger with recursive triggers on."""

TARGETS: dict[str, tuple[str, ...]] = {
    "fkid_declaration_order": ("foreign-key-check-primary-key",),
    "missing_parent_skipped": ("foreign-key-check-missing-parent",),
    "cid_counts_generated": ("table-info-columns",),
    "replace_delete_fires_nothing": ("recursive-triggers-on",),
}
"""The authored case of `conformance.authored_pragmas` that each mutant changes."""

GUARDS: dict[str, str] = {
    "fkid_declaration_order": "rule:Database.keyCheckRows",
    "missing_parent_skipped": "rule:ForeignKeyLink.satisfied",
    "cid_counts_generated": "rule:CatalogTable.infoRows",
    "replace_delete_fires_nothing": "rule:insertRow",
}
"""What each mutant guards: `rule:` and the Lean declaration of its file that the mutant
changes. `conformance.mutant_guards` checks every entry."""
