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
