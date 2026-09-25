# SQL-only formal component status

Created: 2026-09-25. Status: IN PROGRESS — formal certificate checked; integrated
CLI/package validation and owner review remain with the coordinating task.

Task: [SQL-only core](20260925-sql-only-core.task.md). The owner's SQL-only and
independent-business-model corrections supersede the earlier framework model.
This component does not authorize publishing proposed application requirements.

The generic core is checked in 914188f4: version-only engines, supplied transaction
statements, pending versus persisted outcomes, restricted lossless literal DML,
and reached-state support obligations. Its complete kernel gate passed. Generic
row/schema/constraint helpers in 1b376ccb and c7026d2a passed the 22-job library
build without new SQL axioms.

The revised example uses an independent typed History, strict complete decoding,
and equality of business history lists. Physical rowids and raw bookkeeping are
not business entities. Current/result representation invariants contain exactly
six prior successful identities and those six plus the target. The approved
actual-storage mapping guard prevents candidate readers from concealing changed
business values. Required malformed rows reject the entire observation; optional
wrong-type values and noncanonical UUID spellings are explicitly outside the
selected decoder domain. Source fidelity and decoder/witness helpers received
independent conformance-agent review and source-backed implementation.

SchemaBinding derives table declarations from sealed SchemaInputs.startSchema
(the constant is in namespace Generated) and derives the result by appendAt.
schema.sql is the only handwritten full schema. The proposed baseline records
all seven approved modules plus the schema bytes; these hashes are an engineering
proposal and do not assert owner approval. Retired profile.json, copied
AtuinSchema and framework-trace module were removed.

Validation: freshly generated SchemaInputs/SqlInputs using the production pinned
3.46.0 CST parser and frontend; compiled every approved/candidate module, decoder
boundary checks, empty/populated admitted witnesses and final Proofs.migrationCorrect
with exact Lean 4.33.0, bounded per-module timeouts (30/60 seconds). The final
certificate depends only on propext, Classical.choice and Quot.sound. Its
universal theorem covers arbitrary admitted history and catalog rows for the
explicit BEGIN/ALTER/INSERT/COMMIT/UPDATE SQL. Native-engine refinement and live
framework behavior are not claimed. Public CLI staging and installed acceptance
will be checked after integration with the separately reviewed schema-only gate.
