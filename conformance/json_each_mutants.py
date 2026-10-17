"""Mutants of `json_each` in FROM (ADR 0012, amendment 5, slice 6d).

The task of slice 6d lists the changes that the conformance suite must notice. Each
mutant is one text change in a copy of the model, which
`conformance.resolve_mutants.measure` builds and runs against its target case of
`conformance.authored_json_each`.
"""

from conformance.resolve_mutants import SQLITE

EACH = SQLITE + "Json/Each.lean"
"""The rows of `json_each`."""
FUNCTIONS = SQLITE + "QueryFunctions.lean"
"""The `json_each` sources of a query."""
SCOPE = SQLITE + "Resolution/Scope.lean"
"""The names in scope."""

MUTANTS: dict[str, tuple[str, str, str]] = {
    "each_id_as_index": (EACH,
        "    let row ← eachRow context (.integer index) item offset (context.rootPath ++ itemPathStep index)",
        "    let row ← eachRow context (.integer index) item index (context.rootPath ++ itemPathStep index)"),
    "each_array_key_as_text": (EACH,
        "    let row ← eachRow context (.integer index) item offset (context.rootPath ++ itemPathStep index)",
        "    let row ← eachRow context (.text (toString index).toUTF8.toList) item offset\n"
        "      (context.rootPath ++ itemPathStep index)"),
    "each_container_atom": (EACH, "  let atom := if node.isContainer then Value.null else value",
        "  let atom := value"),
    "each_member_id_at_value": (EACH,
        "    let row ← eachRow context key value offset (context.rootPath ++ memberPathStep text)",
        "    let row ← eachRow context key value (offset + jsonbSize label) (context.rootPath ++ memberPathStep text)"),
    "each_not_correlated": (FUNCTIONS, "  match each.cells row with", "  match each.cells [] with"),
    "each_hidden_in_star": (SCOPE,
        "      fun (index, _) => !source.merged.contains index && !source.hidden.contains index).map",
        "      fun (index, _) => !source.merged.contains index).map"),
}
"""Each mutant: the file under `packages/`, the exact text it changes, and the replacement. The
names follow the list in the task of slice 6d: `id` as the element index; `key` of an array
as text; `atom` of a container as its JSON text; the `id` of an object member at its value
instead of its label (the order of the rows is not observable without `ORDER BY`, so the
mutant of reversed rows of the task is this one); `json_each` not re-evaluated for each left
row; the hidden columns shown by `*`."""

TARGETS: dict[str, tuple[str, ...]] = {
    "each_id_as_index": ("each-array",), "each_array_key_as_text": ("each-array",),
    "each_container_atom": ("each-array",), "each_member_id_at_value": ("each-object",),
    "each_not_correlated": ("each-correlated",), "each_hidden_in_star": ("each-array",),
}
"""The authored case of `conformance.authored_json_each` that each mutant changes."""

GUARDS: dict[str, str] = {
    "each_id_as_index": "rule:itemRows", "each_array_key_as_text": "rule:itemRows",
    "each_container_atom": "rule:eachRow", "each_member_id_at_value": "rule:memberRows",
    "each_not_correlated": "rule:EachSource.join", "each_hidden_in_star": "rule:Scope.visible",
}
"""What each mutant guards: `rule:` and the Lean declaration of its file that the mutant
changes. `conformance.mutant_guards` checks every entry."""
