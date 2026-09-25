# SQL-only example and native comparisons

Created: 2026-09-25. Status: DONE (bounded native SQL and coverage component).
Task: [SQL-only core](20260925-sql-only-core.task.md).

Owner correction supersedes framework capture/certification. This component owns
Atuin SQL/README, ordinary native comparisons and coverage, and removal of the
Rust capture/obsolete trace pipeline. Root owns environment/shared recipes/CI
and general docs; lead owns generic semantics and Lean examples; integration
owns frontend and CLI tests. Workspace starts clean at cfa94ddd.

Read pinned Atuin schema/migration/database/history sources directly from GitHub
and SQLx's pinned release source, without importing/building either application.
Web retrieval missed cache; bounded direct GitHub reads succeeded. Exact SQL
proposal accepted by root and lead: BEGIN / original ALTER / all-column INSERT / COMMIT /
timing UPDATE. Timestamp and elapsed are explicit example instantiations; rowid
is omitted as upstream does. Original ALTER checksum remains SHA384, not the
checksum of the wrapper. The source-justified pre-ANALYZE baseline has two tables
and three explicit indexes. Native reserved-name rejection and missing STAT4
support justified not reusing the old captured statistics schema; no writable
schema bypass or native compile-flag change is introduced.

Pinned SQLite 3.46 OP_NewRowid source confirms empty=1, otherwise maximum+1 even
when negative; MAX_ROWID triggers random fallback. A native probe with maximum -2
allocated -1. Lead will expose a generic proved data domain for supported inserts.
No completed proof/conformance claim is made for the revised example yet.


Checked component replaces the Rust/application capture tree, imported catalogs,
and framework native/model adapters with six ordinary SQL comparisons. They
cover empty/singleton/multiple history rows, nullable keys and negative rowids,
the random allocation boundary, and duplicate-key ABORT within BEGIN followed
by explicit ROLLBACK. Full stored observations, metadata, schema and integrity
are checked independently. These tests are explicitly native-only mechanics,
not witnesses of an approved application invariant or model correspondence.

`tests/atuin_sql_test.py` passes all six cases under pinned SQLite 3.46.0;
`tests/coverage_test.py` passes seven tests in 1.015 seconds. Both commands have
30-second outer timeouts; native subprocesses have five-second timeouts. Used
already realized declared Python and SQLite store paths, with no application
build or root-flake evaluation. Coverage consumes one fresh stdout receipt,
checks the exact six identities and raw SQL-byte hashes, and rejects incomplete,
duplicate, failed, stale or model-inflating observations. Receipt is
`build/atuin-sql.json`; aggregate field is `atuin_sql` with denominator six and
one explicitly out-of-domain random-rowid observation. Existing generic proof,
grammar and native/model evidence remain separate.

Root independently reviewed the source and reproduced all six native SQL cases
and seven coverage regressions in the pinned default environment; accepted.
The generic formal example and its final invariant documentation remain peer
work; this status does not claim the overall SQL-only task is complete.

Root-requested follow-up updates the named semantic support inventory to include
explicit transactions and bounded literal INSERT/UPDATE, without treating that
list as a denominator for SQLite semantics. Seven coverage regressions pass.


Follow-up independent source review of checked core 914188f4 covered LiteralData,
SqlExecution, SqlExamples, Contract and the legacy-extension bridge. No concrete
native divergence or vacuity defect found: nonempty admitted states, Conforms,
reached-state readiness and total runSql outcomes remain separate obligations.
Pending outcomes retain both durable snapshot and visible data. Finite negative
rowid, duplicate NULL, constraint ABORT and rollback checks agree with the native
SQL evidence; builds were not redundantly repeated.

README now describes lead-confirmed declaration names for the revised example,
logical missing-shell normalization, independent actual-output resultValid check,
and example-only six-to-seven successful catalog identities. It explicitly marks
the revised proof bundle as pending; peer code is still being checked. This is a
documentation update, not a claim that the new proof has passed.


Lead-delegated bounded witness follow-up replaces AtuinWitness.lean with a
SQL-only file importing Interpretation. Six actual prior version/checksum rows
are retained in emptyState and populatedState. The populated history has two
NULL TEXT primary keys, distinct signed physical rowids, and distinct composite
UNIQUE tuples. Proven obligations include both Admitted states, actual current
invariants, and defined observations with zero/two history rows and six metadata
records. No final VC is claimed by this witness file.

Compiled exact live approved source snapshots into this workspace's
build/sql-only-witness, using the read-only checked formal core library. The
witness check passed in 2.15 seconds under a 30-second timeout, without warnings.
All six public admission/invariant/observation theorem audits contain exactly
propext, Classical.choice and Quot.sound. No author workspace files were written.
Integration depends on lead's forthcoming revised approved source checkpoint.

The earlier raw-row witness follow-up is superseded by the owner business-model
correction; see 20260925-atuin-business-model.status.md. The final typed witness
was handed to lead and is excluded from this component change.

The generated SchemaInputs split is now handled by both single-source concrete
comparison callsites: prepend the production schema module body and remove only
the exact leading SchemaInputs import from the production migration module.
No hand-authored schema or compatibility layer is introduced. Based on integrated
03e5f7c6 plus business model 98c356be, one explicit small Nix session built the
21-job core library and passed all five native/public-runSql comparisons and the
false-empty-row rejection. Build/test outer timeouts were 90/180 seconds and
individual Lean comparisons retain their existing 30-second timeouts.
