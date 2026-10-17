"""Mutants of JSON reading and `json_extract` (ADR 0012, amendment 5, slice 6b).

The task of slice 6b lists the changes that the conformance suite must notice. Each
mutant is one text change in a copy of the model, which
`conformance.resolve_mutants.measure` builds and runs against its target case of
`conformance.authored_json`.
"""

from conformance.resolve_mutants import SQLITE

JSON = SQLITE + "Json/"
"""The JSON functions."""

MUTANTS: dict[str, tuple[str, str, str]] = {
    "json_true_as_text": (JSON + "SqlValue.lean", "  | .true => .ok (.integer 1)",
        "  | .true => .ok (.text \"true\".toUTF8.toList)"),
    "json_arrow_scalar_unquoted": (JSON + "Extract.lean", "  | .ok (some found) => .ok (.text (renderNode found))",
        "  | .ok (some found) => sqlValueOfNode found"),
    "json_last_duplicate_key": (JSON + "Path.lean",
        "    | some (text, rawLabel) => if labelsMatch key rawKey text rawLabel then some (some value) else",
        "    | some (text, rawLabel) => if labelsMatch key rawKey text rawLabel then"
        " some ((findMember key rawKey rest).getD (some value)) else"),
    "json_numbers_rerendered": (JSON + "Render.lean", "  | .int payload | .float payload => payload",
        "  | .int payload => payload | .float payload => (payload.reverse.dropWhile (· == 48)).reverse"),
    "json5_not_normalized": (JSON + "Render.lean", "  | .int5 payload => renderInt5 payload",
        "  | .int5 payload => payload"),
    "json_from_end_as_first": (JSON + "Path.lean",
        "else if byteAt path stop == 93 then some (some (total - back, stop))",
        "else if byteAt path stop == 93 then some (some (back - 1, stop))"),
    "json_missing_path_error": (JSON + "Extract.lean", "  | .notFound => .ok none",
        "  | .notFound => .error .malformed"),
    "json_error_ignored": (SQLITE + "Execution.lean",
        "      else if query.mustFail rows then .failure position .functionError database",
        "      else if false then .failure position .functionError database"),
}
"""Each mutant: the file under `packages/`, the exact text it changes, and the
replacement. The names follow the list in the task of slice 6b: `true` as text; a
scalar of `->` without quotes; the last duplicate key selected; numbers re-rendered
(a REAL without its trailing zeros); JSON5 not normalized; `[#-1]` as the first element;
a missing path as an error. A failing query that succeeds is added."""

TARGETS: dict[str, tuple[str, ...]] = {
    "json_true_as_text": ("json-scalars",), "json_arrow_scalar_unquoted": ("json-arrows",),
    "json_last_duplicate_key": ("json-duplicate-keys",), "json_numbers_rerendered": ("json-containers",),
    "json5_not_normalized": ("json5-forms",), "json_from_end_as_first": ("json-paths",),
    "json_missing_path_error": ("json-missing",), "json_error_ignored": ("json-malformed",),
}
"""The authored case of `conformance.authored_json` that each mutant changes."""

GUARDS: dict[str, str] = {
    "json_true_as_text": "rule:sqlValueOfNode", "json_arrow_scalar_unquoted": "rule:arrowJson",
    "json_last_duplicate_key": "rule:findMember", "json_numbers_rerendered": "rule:renderNode",
    "json5_not_normalized": "rule:renderNode", "json_from_end_as_first": "rule:readPathIndex",
    "json_missing_path_error": "rule:lookupOutcome", "json_error_ignored": "rule:step",
}
"""What each mutant guards: `rule:` and the Lean declaration of its file that the mutant
changes. `conformance.mutant_guards` checks every entry."""
