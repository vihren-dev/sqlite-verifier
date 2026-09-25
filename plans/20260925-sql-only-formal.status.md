# SQL-only formal component status

Created: 2026-09-25. Status: IN PROGRESS.

Task: [SQL-only core](20260925-sql-only-core.task.md). Owner direction supersedes
the previous framework-runner model. This component owns Lean semantics, generic
proof helpers and the revised source-linked application example. It does not
authorize publishing proposed application requirements or refreshing protected
baselines without their separate review.

The generic core is checked in 914188f4: version-only profiles, script-directed
transactions, explicit pending versus persisted storage, restricted literal DML,
and mandatory generic support obligations. Its complete kernel gate passed.

Added derived schema/row helpers in LiteralPreservation: replacing rows preserves
schema conformance, normal next-rowid allocation exceeds every old rowid, bounded
INSERT preserves widths and distinct signed rowids, and appending a fresh key
preserves uniqueness. `timeout 60 lake build SqliteVerifier` passed 22 jobs. No new
axioms, native allocation oracle or frame assumption is introduced.

The example rewrite is in progress. The approved before/after invariants will
retain exactly the six prior successful identities and those six plus the target.
Missing shell and actual SQL NULL normalize to the same application observation;
an approved resultValid predicate independently reads actual shell cells so a
constant-unknown result reader cannot mask incorrect initialization. All SQL
effects, including INSERT/COMMIT/UPDATE, are supplied explicitly. Arbitrary old
history remains admitted; rowid allocation restrictions concern the metadata
table. No revised example proof or full aggregate success is claimed yet.
