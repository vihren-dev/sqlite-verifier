# SQL-only core cleanup status

Created: 2026-09-25. Status: IN PROGRESS.

Task: [sql-only-core.task.md](20260925-sql-only-core.task.md).
Authority: owner's explicit SQL-file universal-interface correction, 2026-09-25.
Starting revision: d6c46ef1. Lean toolchain is pinned by lean-toolchain; the Nix
environment stays isolated in nix/. No framework or application execution is a
product requirement. Owner review of application meaning remains separate from
mechanical validation.

Progress: audited the profile-to-execution coupling; preparing source-backed SQL
example and removal of SQLx semantics, capture infrastructure and documentation.
Validation: pending implementation. No claim of equivalence or passing tests yet.

## Generic formal core checkpoint

Removed RunnerProfile, RunnerExecution and RunnerFootprint. Profiles now contain
only the pinned SQLite version. The supplied Statement syntax includes explicit
BEGIN/COMMIT/ROLLBACK, full ordered literal INSERT and single-literal UPDATE under
an integer equality predicate. No framework inserts, timing updates, optimizer
writes or rollback are inferred. Outcome.pending exposes both the committed
snapshot and visible connection storage, including the failing statement index.

LiteralData admits identity affinity conversion, INTEGER/NULL unique-key
comparison, ordinary nullable primary keys, NOT NULL and ABORT constraints.
Ordinary rowid allocation is exactly empty=1 or largest+1, including negative
largest identities; random allocation at the signed maximum is excluded by an
explicit checked support obligation. Every reached DML statement must satisfy
the generic data domain. Initial Admitted includes schema conformance, widths
and distinct signed rowids. The additive proof helpers additionally require an
all-extension syntax guard and the CREATE/index namespace guard, so their legacy
invalid-statement result cannot certify DML or transaction behavior.

Validation in the existing pinned tiny Nix shell: `timeout 90 lake build
SqliteVerifier` passed 21 jobs, including finite kernel assertions for complete
transactional writes, nullable keys, negative rowids, ABORT with a pending ALTER,
explicit rollback, open-transaction EOF, invalid transaction control, unsupported
coercions and the rowid-allocation boundary. Existing ordinary, reversed and
allowed-failure universal proofs retain only propext/Classical.choice/Quot.sound.
`timeout 360 python3 tests/kernel_gate_test.py` passed honest proofs/refutations
and all adversarial rejection cases, including a candidate 3.51 convenience
target attempting to substitute for sealed 3.46 input. The gate reconstructs the
same complete argument list; no generated-target alias is trusted.

This is a bounded core unit, not completion of the task or a native refinement
claim. The revised Atuin example proof and generic SQL/native comparisons remain
in progress. Old Atuin Lean files are intentionally not counted as checked at
this checkpoint. Their replacement must retain six-prior to seven-successful
catalog identities in example-only before/after invariants, alongside arbitrary
admitted history and exact old bookkeeping preservation. No application catalog
belongs in the core or execution profile.
