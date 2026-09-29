# Concrete native/model comparisons

ADR 0004's W1–W2 prototype uses one Lean `classifyCase` function for compiled
comparison and its `checkCase` predicate for kernel proofs. The
[version-one format](conformance-format-v1.md) includes explicit initial rows,
production-translated SQL, and native initial/per-statement observations.

Inside the pinned Nix shell:

```sh
just conformance --repeat 3 --prove
nix-build build-support/default.nix -A tests.model --no-out-link \
  --option sandbox true --option sandbox-fallback false \
  --extra-experimental-features 'nix-command flakes'
```

The first command writes JSON cases, decoded Lean regression terms, and measured
native-plus-compiled throughput to `build/conformance-evidence/`. Kernel proof
time is excluded from the reported throughput. The conformance executable is a
separate test build; it adds no shipped verifier command. `just test` includes the
same Nix model target, without executing it twice on the host.

The [review validation report](../reports/20260929-adr4-review-validation.json)
records 15 agreements and 42 native observations in 1.039 seconds on Darwin arm64:
0.755 seconds of native acquisition and 0.284 seconds for one compiled batch,
including JSON transport and process startup (14.44 cases/second end to end).
Proof-term emission and all five kernel checks run outside that timer. This is a
warm five-case DDL workload, not pure evaluator or generator-scale throughput;
Linux was not executed locally. The report includes source hashes and runtime
identities. The [original report](../reports/20260929-adr4-prototype.json) is retained
as historical evidence from before connection, metadata and streaming corrections.

## Preserved authored cases

The five cases in `conformance/model_cases.py` retain their original independent
fixtures and final expectations. Native results are checked against those
expectations before the same decoded case receives a compiled verdict and a
kernel proof. Their authored native diagnostic substrings and exact modeled
failure categories/positions are also retained, independently of the generic
primary-code comparator. No expected value is derived from the model.

| Derived case | Required independent observation |
| --- | --- |
| ADD then CREATE | All three old rowids and integer/text/NULL cells survive; appended cells are NULL; audit table is empty. |
| ADD then conflicting CREATE | ADD remains committed; later table creation is not reached. |
| CREATE then duplicate-column ADD | New audit table remains committed; old invoices remain unchanged. |
| CREATE then missing-table ADD | New audit table remains committed; missing-table error occurs at statement 1. |
| ADD at 2000 columns with a duplicate name | Column-limit error takes precedence over duplicate-column error; all columns and empty contents remain. |

All five fixtures survive JSON decoding unchanged, including rowids `-4`, `9`,
`22`, NULL, UTF-8 text and the 2000-column table. Their former separate model
assertions were replaced only after native replay through the persistent runner
agreed. The lost-row negative check now rejects a proof of the shared predicate.
Imported `alter3` fixtures and their expectations are unchanged.

`conformance/cases/` freezes the five version-one native records. Every model test
re-executes its original SQL and requires equality with that frozen record before
compiled and kernel checking. The files came from `just conformance --prove`;
regeneration requires the pinned native runner, never hand-editing a trace to
make a disagreement disappear.

## Additional bounded checks

- Transactions: admitted literal INSERT and UPDATE, commit, rollback, an open
  transaction at EOF, nested BEGIN, and a uniqueness failure. Errors preserve
  earlier visible writes and the original committed snapshot; later statements
  are not executed.
- Admission: unsupported SQL, a `statementReady` data-domain rejection, and
  `invalidDefinition` never count as agreement. Unsupported decoded cases also
  receive kernel proofs that `checkCase` is false.
- Storage and metadata: exact REAL bits, TEXT with invalid UTF-8/NUL, empty and
  nonempty BLOB, NULL, a populated 2000-column table, declaration aliases,
  timestamp defaults, primary/unique keys, and an explicit unique index.
- Failure detection: a wrong trace and falsely empty rows fail the compiled check
  and cannot acquire agreement proofs. An isolated production-model mutation
  that drops INSERT produces disagreement in compiled and kernel evaluation.
- Harness failures: a real exclusive SQLite lock prevents committed-state
  observation and returns `HARNESS_ERROR`; malformed JSON, versions and bytes
  also fail closed. A malformed input line does not poison the next valid line.

The model trace's final observation is proved equal to observing `runSql`, for
all scripts and initial databases. Finite case comparisons additionally use the
production `SupportedSql` checks. None of these statements proves universal
native refinement, arbitrary application-query preservation, or pilot acceptance.

## Native boundary and limits

The C-API runner loads the library beside the Nix-pinned SQLite executable,
checking version 3.51.0, exact source ID and MAX_COLUMN=2000. Each connection
verifies library-default DQS_DML=1 and DQS_DDL=1 with `sqlite3_db_config`;
the pinned engine retains its default build configuration. Connections use native
autocommit, defensive mode off, trusted schema on, and writable schema off.

Native columns are cross-checked against `table_xinfo` (including type, independently
derived affinity, nullability, default and primary-key order). `index_list` and
`index_xinfo` independently check uniqueness, ordered keys, collation and explicit
index identity. A translator mismatch is a harness error, never agreement. The
affinity check follows [SQLite’s ordered rules](https://sqlite.org/datatype3.html#determination_of_column_affinity).

Per-statement observations retain primary and extended error codes; comparison
uses primary codes at the current model's granularity. TEXT/BLOB use bytes and
REAL uses its 64-bit pattern. Fixture cells use C-API parameter binding, including
positive and negative infinity. SQLite binds NaN as NULL: a requested NaN REAL
therefore produces an initial-state disagreement, not an invalid-SQL harness error. A second connection observes committed state while
a transaction is open. Contention that prevents observation is a harness failure,
not semantic evidence. Native statements have a five-second progress deadline
and a 100 ms lock wait; outer test/recipe deadlines also bound complete runs.
Native schema parsing is cached by the actual declaration text within each case,
shared by visible and committed observations, so rollback cannot reuse metadata
from a different schema with the same schema version. Benchmark cases are sent
through one JSON-lines runner process; reports separate native acquisition and
compiled batch time (including transport). Optional proof-term emission and kernel
checks run separately, outside the timing.
Parsing is bounded to five seconds, each compiled batch to 30 seconds, and
concrete kernel checks to 120 seconds (including the wide case).

The denominator remains **five authored derived cases**, plus the specifically
listed regression scenarios. There is no generated corpus yet. W3 requires owner
review of prototype evidence. Imported `alter3` observations remain
`NOT_YET_MODEL_CHECKED` because their inherited view dependency is unsupported;
no view was removed to inflate conformance coverage.
