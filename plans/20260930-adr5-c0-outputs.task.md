# ADR 0005 C0: statement outputs, parameters and comparison

Created 2026-09-30. Status: DONE 2026-10-01.
Status: [progress](20260930-adr5-c0-outputs.status.md).
Spec: [ADR 0005 §3.1](../docs/adr-0005-conformance-corpus-scale.md#31-case-format-v2-outputs-and-parameters).
Overall: [reference corpus](20260930-adr5-reference-corpus.task.md).

## Observable outcomes

Version-two evidence records each statement's exact SQL, typed bound parameters,
result column names/count even for empty results, typed rows, and direct DML
change count. Ordered queries carry faithful SQLite tie groups; cutoff groups
are complete and comparison preserves row multiplicity. RETURNING is unordered.
Supplementary probes cannot write and use the same state and inputs. Unobservable
tie structure or unspecified selection inside a write has a named exclusion.

The Lean comparator compares outputs and state together through `classifyCase`.
Missing output capability is MODEL_UNSUPPORTED, not agreement; recording can
precede model query semantics. Existing admitted DDL/literal writes can exercise
the comparison without adding query semantics to the production model. V1
records and verdicts survive the new decoder and replay path unchanged.

## Behavioral tests

Native cases exercise typed positional/named parameters, empty output shape,
RETURNING, direct counts after SELECT and trigger/cascade changes, zero-row
UPDATE, unequal/equal keys, INTEGER/REAL and NOCASE ties, SELECT DISTINCT,
one/two boundary cuts, duplicate-row rejection, unordered RETURNING acceptance,
and rejection of a writing probe. Pure compiled/kernel comparison checks reject
corrupted shape, row, group order, duplicate row and count. Unsupported queries
remain unsupported. Existing model/native/trace regressions and v3 replay verify
backward compatibility. Tests and subprocesses have explicit short timeouts.

## Tricky points and relevant sources

`native_record.execute` currently splits scripts through SQLite's prepared tail;
it must preserve trigger bodies and stop at the first error. `Connection.bind`
already preserves storage classes; reuse it, and verify binding cardinality.
`native_replay.model_case` aligns native SQL with the production parser and strips
outputs today. The model's `advance` remains the execution authority; test
comparison must not introduce another SQL evaluator. Structural value encoding
is shared with the production bundle checker and must remain compatible.
Use SQLite-native ordering evidence instead of appending columns blindly to
DISTINCT/grouped/compound queries. Native snapshots are diagnostic state evidence,
not an oracle for direct changes or pre-trigger RETURNING values.
