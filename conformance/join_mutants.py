"""Mutants of joins (ADR 0012, amendment 2, slice 4).

The amendment lists the changes that the conformance suite must notice. Each mutant is
one text change in a copy of the model, which `conformance.resolve_mutants.measure`
builds and runs against its target case of `conformance.authored_joins`.
"""

from conformance.resolve_mutants import SQLITE

QUERY_JOINS = SQLITE + "QueryJoins.lean"
"""The rows of joins."""
SCOPE = SQLITE + "Resolution/Scope.lean"
"""The resolution of unqualified names over the sources."""
SOURCES = SQLITE + "Resolution/Sources.lean"
"""The resolution of the tables of FROM and their names."""
QUERIES = SQLITE + "Resolution/Queries.lean"
"""The resolution of SELECT and its result columns."""

PADDED = "    if (joinMatches row join table).isEmpty then [row ++ List.replicate table.shape.columns.length .null]"
"""The left join's row for a left row without a match."""

MUTANTS: dict[str, tuple[str, str, str]] = {
    "left_join_drops_unmatched": (QUERY_JOINS, PADDED, "    if (joinMatches row join table).isEmpty then []"),
    "left_join_pads_left_values": (QUERY_JOINS, PADDED,
        "    if (joinMatches row join table).isEmpty then\n"
        "      [row ++ (row ++ List.replicate table.shape.columns.length (.null : Value)).take table.shape.columns.length]"),
    "on_after_padding": (QUERY_JOINS, PADDED,
        "    if (joinMatches row join table).isEmpty then\n"
        "      [row ++ List.replicate table.shape.columns.length .null].filter fun joined =>\n"
        "        join.condition.all fun condition => truthy (condition.eval joined)"),
    "unqualified_takes_first_source": (SCOPE, "      else .ambiguous)", "      else .found first reads)"),
    "alias_keeps_table_name": (SOURCES,
        "{ name := reference.alias.getD reference.table, columns := table.columns }",
        "{ name := reference.table, columns := table.columns }"),
    "star_omits_joined_columns": (QUERIES,
        "      .ok (scope.visible.map fun (position, defined) =>",
        "      .ok ((Scope.visible (scope.take 1)).map fun (position, defined) =>"),
}
"""Each mutant: the file under `packages/`, the exact text it changes, and the
replacement. The names follow the list in the amendment: a left join drops the
unmatched left rows; it pads with the left row's values instead of NULL; it applies ON
after the padding, as WHERE does; an unqualified name of two sources takes the first
source instead of SQLite's ambiguous-name error; the table name instead of the alias
names an aliased source; and `*` omits the columns of the joined tables."""

TARGETS: dict[str, tuple[str, ...]] = {
    "left_join_drops_unmatched": ("join-left-unmatched",), "left_join_pads_left_values": ("join-left-unmatched",),
    "on_after_padding": ("join-left-condition-in-on",), "unqualified_takes_first_source": ("join-ambiguous-column",),
    "alias_keeps_table_name": ("join-alias-hides-table",), "star_omits_joined_columns": ("join-cross",),
}
"""The authored case of `conformance.authored_joins` that each mutant changes."""

GUARDS: dict[str, str] = {
    "left_join_drops_unmatched": "rule:joinRow", "left_join_pads_left_values": "rule:joinRow",
    "on_after_padding": "rule:joinRow", "unqualified_takes_first_source": "rule:Scope.resolveStep",
    "alias_keeps_table_name": "rule:resolveTableReference", "star_omits_joined_columns": "rule:resolveResultColumn",
}
"""What each mutant guards: `rule:` and the Lean declaration of its file that the mutant
changes. `conformance.mutant_guards` checks every entry."""
