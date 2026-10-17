"""Mutants of `json_type`, `json_valid`, `json_array_length` and `json` (ADR 0012,
amendment 5, slice 6c).

The task of slice 6c lists the changes that the conformance suite must notice. Each
mutant is one text change in a copy of the model, which
`conformance.resolve_mutants.measure` builds and runs against its target case of
`conformance.authored_json_functions`.
"""

from conformance.resolve_mutants import SQLITE

FUNCTIONS = SQLITE + "Json/Functions.lean"
"""`json_type`, `json_array_length` and `json`."""
VALID = SQLITE + "Json/Valid.lean"
"""`json_valid`."""

MUTANTS: dict[str, tuple[str, str, str]] = {
    "json_large_integer_real": (FUNCTIONS, "  | .int _ | .int5 _ => \"integer\"",
        "  | .int payload | .int5 payload => if payload.length > 18 then \"real\" else \"integer\""),
    "json_valid_accepts_json5": (VALID, "  else standardJson bytes || flags / 2 % 2 == 1", "  else Bool.true"),
    "json_valid_fails_malformed": (VALID,
        "      .ok (.integer (if (valueText json).any (textValid flags ·) then 1 else 0))",
        "      if (valueText json).any (fun bytes => (parseJsonText bytes).isNone) then .error .malformed\n"
        "      else .ok (.integer (if (valueText json).any (textValid flags ·) then 1 else 0))"),
    "json_valid_flags_ignored": (VALID, "  if !flagsAccepted flags then .error .badFlags",
        "  if false then .error .badFlags"),
    "json_object_length": (FUNCTIONS, "    | .textraw _ | .object _ => .integer 0",
        "    | .textraw _ => .integer 0\n    | .object members => .integer members.length"),
    "json_not_minified": (FUNCTIONS, "  selectedValue (selectNode json none) fun node => .text (renderNode node)",
        "  selectedValue (selectNode json none) fun _ => json"),
}
"""Each mutant: the file under `packages/`, the exact text it changes, and the
replacement. The names follow the list in the task of slice 6c: a large integer typed
`real`; `json_valid` accepting JSON5 without flag 2; `json_valid` failing on malformed
text; the flags error ignored; `json_array_length` of an object as its member count; `json`
returning its argument as written."""

TARGETS: dict[str, tuple[str, ...]] = {
    "json_large_integer_real": ("json-type-numbers",), "json_valid_accepts_json5": ("json-valid-strict",),
    "json_valid_fails_malformed": ("json-valid-strict",), "json_valid_flags_ignored": ("json-valid-flags-error",),
    "json_object_length": ("json-array-length",), "json_not_minified": ("json-minify",),
}
"""The authored case of `conformance.authored_json_functions` that each mutant changes."""

GUARDS: dict[str, str] = {
    "json_large_integer_real": "rule:JsonNode.typeName", "json_valid_accepts_json5": "rule:textValid",
    "json_valid_fails_malformed": "rule:jsonValid", "json_valid_flags_ignored": "rule:jsonValid",
    "json_object_length": "rule:jsonArrayLength", "json_not_minified": "rule:jsonText",
}
"""What each mutant guards: `rule:` and the Lean declaration of its file that the mutant
changes. `conformance.mutant_guards` checks every entry."""
