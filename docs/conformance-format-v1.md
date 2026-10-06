# Conformance case format v1

ADR 0004's test-only `conformance-runner` accepts one JSON object per line and
returns one result per line. `StructuralCodec.lean` owns the codecs for schema
declarations, statements, values and profiles; `VerifierConformance/Json.lean` adds
the conformance case and observation records. The Python encoders are in
`migration_check/structural.py`, re-exported by `conformance/case_format.py`.
ADR 0003's `verify-bundle` uses the same codecs for its generated-inputs record
(see the [data path guide](data-path.md)); that record keeps indexes in declaration
order, as the Lean emitter does, where conformance cases order them by name.

## Record

All fields are required in JSON, including empty metadata lists:

| Field | Meaning |
| --- | --- |
| `version` | Integer `1` for this format; [v2](conformance-format-v2.md) adds outputs. Unknown versions are harness errors. |
| `schemaSql`, `migrationSql` | Original SQL, kept separately. |
| `schema` | Production `starting_schema` result, as structural table declarations. |
| `initial` | Finite array of `[tableName, table]` pairs with explicit physical rowids. |
| `script` | Structural production statements in execution order. |
| `nativeTrace` | Initial observation, then one observation per executed statement. |
| `requirements` | Array of requirement-ID strings; optional evidence expressed as `[]`. |
| `provenance` | Array of `[key, value]` string pairs, including fixture name and engine source ID. |

A table has `columns`, `rows`, and `properties`. A schema declaration has `name`,
`columns`, and `properties`. Rows have integer `rowid` and ordered `values`.
Columns have `name`, `affinity`, `declaredType`, `notNull`, and `defaultValue`.
Properties retain `primaryKey`, `uniqueKeys`, and explicit `indexes`; each index
retains `name`, `columns`, and `unique`. Enum tags use the Lean constructor names.
`defaultValue` is JSON null or `"currentTimestamp"`.

Values preserve storage classes:

```json
["null", {"integer":{"value":-4}}, {"real":{"bits":"4609434218613702656"}},
 {"text":{"bytes":[99,97,102,195,169]}}, {"blob":{"bytes":[0,255]}}]
```

REAL payloads are unsigned 64-bit decimal **strings**, avoiding JSON consumers'
floating-point precision loss. Bytes are integers in 0..255. Physical rowids are
signed 64-bit integers; duplicate table names, duplicate rowids, and incorrect row
widths are rejected by the decoder. Native initialization failures are harness
errors. Initial observations detect affinity changes or other differences between
the supplied fixture and its actual stored representation. Fixture setup binds
REAL values through the C API: infinities survive, while NaN becomes native NULL
and disagrees with a requested NaN REAL in the initial-state comparison.

## Statements and observations

Nullary statements are strings: `"beginTransaction"`, `"commit"`, `"rollback"`.
Other constructors are single-key objects with named fields:

| Tag | Fields |
| --- | --- |
| `createTable` | `name`, `columns` |
| `addColumn` | `table`, `column` |
| `insert` | `table`, `columns` (names), `values` |
| `update` | `table`, `column`, `value`, `key`, `equals` |

An observation contains `visible`, `persisted` (finite table arrays),
`transactionOpen`, `primaryCode`, and `extendedCode`. Code zero means success.
While a transaction is open, `persisted` is read on a second connection. Otherwise
it is the same snapshot as `visible`. Both codes are retained, and the decoder
requires `extendedCode % 256 == primaryCode`.

The current model compares **primary** codes: success 0, `constraintViolation` 19,
and other modeled execution errors 1. Extended codes remain diagnostics because
the model does not distinguish constraint subtypes. Error messages are not compared.
`invalidDefinition` is unsupported admission, not a native error.

Schema SQL is read independently from `sqlite_schema` and normalized through the
production schema frontend, then checked against independent `table_xinfo`,
`index_list` and `index_xinfo` observations and a separate affinity implementation.
Declarations are parsed once per distinct schema within a case. Implicit indexes are represented by their owning
constraints. Explicit indexes are ordered by name. Typed row reads use the C API,
with column-bounded queries for wide tables. Table and row order are canonical;
comparison includes absent names from the fixture, statements, and native states.

## Evidence boundary

`classifyCase` compares the initial states, checks production admission, then
compares every reached observation. Missing or extra observations disagree.
`DISAGREE` has a zero-based statement `position`, or null for an initial mismatch.
`MODEL_UNSUPPORTED` can never satisfy `checkCase`. Frontend rejection happens
before a Lean case exists. Native observation and decoding failures report
`HARNESS_ERROR`; the checker is not invoked on failed native acquisition.

The runner trusts that SQL was translated and observations were acquired by the
harness. Supplying a fabricated JSON trace does not establish native evidence.
`--emit-lean` returns the decoded record and its closed Lean term. Kernel
regressions first use `#guard` to verify the elaborated term re-encodes to the
original case JSON, then prove `checkCase fixture = true` with
`decide +kernel`; there is no second Python comparator or source emitter for SQL.
Axiom audits reject `sorryAx`, `ofReduceBool`, and `_native` names.

The final observation of the model trace is proved equal to observing `runSql`.
This is a model theorem, not a proof about the C library, codec, or harness.
