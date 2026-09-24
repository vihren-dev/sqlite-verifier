"""Declare the bounded audit scope without treating an inventory as measured coverage."""

THEOREMS: tuple[str, ...] = (
    "SqliteVerifier.Examples.all_scripts_execute",
    "SqliteVerifier.Examples.all_scripts_preserve",
    "SqliteVerifier.Demonstration.migrationCorrect",
    "SqliteVerifier.Demonstration.reverseMigrationCorrect",
    "SqliteVerifier.Demonstration.failureMigrationCorrect",
    "SqliteVerifier.violates_required_schema",
)

CLAIMS: tuple[dict[str, str], ...] = (
    {"reference": "R-42316-09582", "snapshot": "conformance/upstream/e_createtable.test:854",
     "claim": "Omitted defaults yield NULL", "model": "SqliteVerifier/Model.lean: Table.appendColumns",
     "evidence": "alter3-3.2; derived ADD then CREATE; all_scripts_preserve"},
    {"reference": "R-25473-20557", "snapshot": "conformance/upstream/e_createtable.test:1059",
     "claim": "Column count is bounded", "model": "SqliteVerifier/Execution.lean: step",
     "evidence": "derived 2000-column error precedence; native MAX_COLUMN pin"},
    {"reference": "R-27775-64721", "snapshot": "conformance/upstream/e_createtable.test:1074",
     "claim": "Runtime limits can be lowered", "model": "Excluded: profile fixes limit at 2000",
     "evidence": "REFERENCE_ONLY; lowering the runtime limit is not exercised"},
    {"reference": "lang_altertable.html#alter_table_add_column",
     "snapshot": "conformance/upstream/lang_altertable.html",
     "claim": "ADD appends a column", "model": "SqliteVerifier/Model.lean: Table.appendColumns",
     "evidence": "derived ADD cases and model preservation; physical no-rewrite claim unmeasured"},
    {"reference": "limits.html#max_column", "snapshot": "conformance/upstream/limits.html",
     "claim": "Default maximum column count is 2000", "model": "SqliteVerifier/Model.lean: maximumColumns",
     "evidence": "native MAX_COLUMN pin and derived boundary case"},
)

EXCLUSIONS: tuple[str, ...] = (
    "No proof of native SQLite C refinement or parser equivalence",
    "No instrumented grammar-production execution coverage",
    "No denominator for all documented SQLite behavior or the full upstream corpus",
    "No runtime-expanded Tcl case count; retained alter3 view remains unsupported by the model",
    "No native storage-layout, schema-cookie, coercion, or arbitrary-query proof",
    "No real-pilot acceptance or owner approval inferred from engineering evidence",
)
