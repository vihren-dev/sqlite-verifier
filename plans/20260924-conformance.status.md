# Native conformance fixture status

Created: 2026-09-24. Status: IN PROGRESS.
Parent task: [Step 1](20260924-step-1-schema-extensions.task.md).
Owner: conformance_review. Challenger: technical_lead.
Workspace: sqlite-verifier-parser. Base: 2f5a83f5.

Outcome: faithfully retain selected upstream alter3-3.1 (both occurrences) and
alter3-3.2 SQL and expected assertions, necessary configuration/setup, and exact
provenance. Replay on pinned native SQLite, reporting native observations
separately from production parser and formal-model status.

Required checks: source hashes, exact extraction, duplicate identifier ordering,
unchanged upstream expectations, native source/version/column-limit pin, old
values/new NULLs/schema side effects, clear not-yet-model-checked reporting.
All subprocesses have explicit short timeouts.

Known constraint: prior alter3-2.5 leaves view v1 in the selected slice's schema.
The importer preserves this dependency rather than silently dropping it to fit
the restricted semantic subset. Full upstream Tcl execution is not claimed.

Implementation checks pass: exact three-instance extraction and source hashes,
all original expectations on pinned native engine, production parsing of every
selected block, final rowids/NULLs/view/schema version. Native fixture execution
revealed shell defensive mode ignores schema_version writes; setting defensive
OFF restores upstream Tcl-connection behavior and final version 11.

Validation: SQLITE3=/nix/store/snlk5qqf7gbjk465rrwzxsn14mx3znh0-sqlite-verifier-native-3.51.0/bin/sqlite3
python3 tests/conformance_native_test.py. 3 selected assertions pass; model and
semantic translation explicitly unchecked. No shared justfile changes.

Denominators: 59 textual assertion sites/55 distinct IDs in alter3.test; selected
3 instances/2 IDs. Four prior SQL setup actions are not counted as assertions.
Independent technical-lead review remains pending.
