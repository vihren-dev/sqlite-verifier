# Atuin finite runner trace comparison

`tests/conformance_atuin_runner_model_test.py` compares two actual SQLx 0.9 traces
against the checked `ProfileExecutes` relation. Each starts with the persisted
ten-object schema, six applied migration records and three independently expected
history rows. Production SQLite3.46 parsing and translation bind the unchanged
target SQL and complete schema. Actual physical rowids, checksum bytes, timestamps,
execution times and every statistics row are embedded in the concrete Lean state.

The normal success trace uses the captured runner configuration unchanged. The
second trace installs a SQLite authorizer that denies exactly the post-COMMIT
UPDATE of `_sqlx_migrations.execution_time`. It records the observed denied call,
leaves all schema definitions intact, and retains the inserted sentinel `-1`.
This is **fault-instrumented evidence**, not a failure claim for the unmodified
Atuin configuration. Existing trigger-based diagnostics remain separate and are
not admitted as this baseline.
The harness retains one acquired SQLx connection to bind the authorizer to that
connection; it calls the real Migrator API and clears caches only after success,
matching Atuin's error-return ordering. It does not run the Atuin application or
its background compactor.

Both proofs establish complete starting conformance, SQLx readiness, the actual
payload result, exact metadata insertion and the allowed statistics-maintenance
footprint through pool closure. All six old bookkeeping records and the seventh
inserted record participate; metadata is not abstracted to an empty table.
History values remain independent expected fixtures, including nullable TEXT
keys, signed rowid extremes and mixed stored classes. These are finite trace
checks, not a universal refinement proof of SQLite or SQLx.

The audit requires exactly `checkedTrace`, `checkedReady`, `before_conforms` and
allows only `propext`, `Classical.choice`, `Quot.sound`. A negative test changes
the inserted migration version in the expected final metadata and requires the
kernel check to fail. No axioms are introduced to bridge native observations.

After building the parsers, Lean library and locked capture binaries, run inside
the declared capture shell:

```sh
timeout 240 python3 tests/conformance_atuin_runner_model_test.py
```

Native calls are bounded by30 seconds; each Lean call by60 seconds. Only after
both traces and the negative regression pass does the test emit JSON and write
`build/atuin-runner-model.json`. The two exact case identities are `success` and
`timing_authorizer_failure`. Each reports its instrumentation scope, six/seven
metadata rowids, statistics counts, theorem/axiom audit and SHA256 hashes of the
raw trace, generated proof and target SQL. Corresponding raw JSON and `.lean`
files remain under `build/atuin-runner-model/`.

This evidence is separate from the three payload-only cases documented in
[atuin-model-conformance.md](atuin-model-conformance.md). Neither denominator is
a claim to cover all native outcomes, values or SQL statements.
