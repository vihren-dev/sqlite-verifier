# Atuin payload native/model comparison

This comparison covers three explicitly derived history fixtures: empty, one
row and three rows. It uses the unchanged original shell migration, the complete
persisted ten-object schema, the production SQLite 3.46 CST/translation pipeline,
the real SQLx 0.9 runner and Lean kernel-checked concrete assertions.

`conformance/atuin_cases.py` independently specifies stored classes and bytes
after SQLite affinity conversion. The native fixture contains NULL TEXT primary
keys, signed rowid extremes, repeated command values, REAL/TEXT/BLOB in INTEGER
affinity fields, embedded-NUL TEXT and a non-UTF8 BLOB. Native observations before
the migration, after it and after pool closure must match those expectations.
Every old row observes a NULL shell value. Complete native schema definitions
must match the captured schema, including metadata, constraints and statistics.

Generated Lean checks schema validity, concrete history-row validity and model
conformance, successful payload execution, exact expected history cells/schema
and unchanged other modeled tables. Expected results come from the independent
fixtures and native schema capture, not from the model's transition function.
A negative test replaces the expected three-row result with an empty table and
requires kernel checking to fail. Proofs use `decide +kernel`, not `native_decide`.

This unit deliberately compares the **payload history and schema**, not the full
SQLx invocation relation. Non-history model tables have empty abstract rows: the
payload does not inspect them. It does not establish SQLx readiness from those
abstract rows or pretend they equal the native bookkeeping/statistics rows.
The report states `full_runner_relation: NOT_YET_COMPARED`. Full runner traces
require a separate comparison with the actual bookkeeping and statistics data.

After building the pinned parsers, Lean library and locked capture binaries:

```sh
nix develop path:./nix#capture --command timeout 180 python3 tests/conformance_atuin_model_test.py
```

Individual native invocations have 30-second limits; each Lean check has a
45-second limit. Reports are written to `build/atuin-model-payload.json`, with
raw native observations and generated proof files under
`build/atuin-model-payload/`. These three finite comparisons support native
correspondence; they do not prove the SQLite C engine or exhaust all valid rows.
