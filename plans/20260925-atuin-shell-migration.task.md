# Verify Atuin's unchanged shell-history migration

Created: 2026-09-25. Status: SUPERSEDED.

The owner replaced the runner-capture/certification requirements with the
[SQL-only core task](20260925-sql-only-core.task.md). The text below records
the historical scope and is not the current acceptance contract.

## Outcome and authority

The owner selected Atuin and authorized extending support to verify the proposed
real migration. The target is `crates/atuin-client/migrations/20260709214605_shell.sql`
at Atuin revision `5b10eb09c664d316b7384210399b02e6127f4027`. Its statement adds
the nullable `shell TEXT` column to `history`. Preserve the original SQL bytes.
The previous [candidate assessment](../docs/pilot-candidates.md) records the
known compatibility gaps; it did not establish a complete application capture.

This is required work toward [Step 1](20260924-step-1-schema-extensions.task.md),
under the engineering brief's input binding, all-outcome guarantees, independent
proof checking, native correspondence and explicit execution-profile rules.
Selection authorizes the necessary schema/profile support; it does not waive
human review of the resulting logical requirements or final pilot acceptance.

## Observable acceptance

An independently reproducible capture supplies the complete actual starting
history-database schema, original migration SQL, resulting schema, upstream
revision/dependency identities and relevant execution configuration. Include
SQLx migration bookkeeping and all relevant constraints and indexes; do not
remove objects or weaken definitions to enter the current subset. Distinguish
reconstructed application DDL from a capture through the real migration runner.
Pin any additional capture dependencies in the project's development environment.

The normal public CLI accepts that complete starting schema and checks a proof
for the unchanged migration under an explicitly identified supported execution
profile. Its generated inputs bind the complete schema, statement sequence,
profile/configuration and interpretation/requirements dependencies. Preserve the
existing simple autocommit workflow. No filename, project-name, expected hash or
exact SQL-text special case may substitute for reusable semantic support.

The proposed pilot contract preserves every existing history row's physical
rowid and all its old stored fields, including the separate stored `id` value;
adds the `shell` column with NULL on old rows; preserves relevant existing
schema properties; and states applicability and every modeled failure outcome.
Cover empty and nonempty admissible histories without assuming away troublesome
states. SQLite's nullable TEXT PRIMARY KEY behavior must not become an implicit
nonnull-ID assumption. Any stronger application invariant must be explicit.

Represent admitted baseline constraints, indexes and metadata faithfully enough
to justify the claim. Prove preservation for arbitrary admitted stored data,
using the public proof library and the independent kernel gate. Unsupported
constraints, expression/index forms, collations, triggers or runtime dependencies
continue to reject. A checked negative result remains distinct from failure to
construct a proof. No new axioms or hidden premises are permitted.

The certified boundary accounts for the actual enclosing transaction protocol
and relevant runner bookkeeping. Do not present an autocommit-only proof as a
proof of a different runner. Any behavior outside the certified boundary must
be explicit and shown not to invalidate the history-preservation claim. This
task does not certify Atuin sync, encrypted record storage or every application
query, and does not introduce an arbitrary migration execution command.

The installed verifier, examples, documentation and coverage report describe
the new supported subset accurately. Existing approved examples and adversarial
gate/baseline checks remain valid. The team presents concrete pilot artifacts
and understandable requirements for owner review. Actual human authoring,
repair and review effort is recorded separately from agent work; no synthetic
measurement or assumed acceptance completes Step 1.

## Required evidence

- End-to-end CLI verification of the unchanged migration with the complete
  captured schema, followed by checking the installed native package.
- Kernel-checked arbitrary-data preservation, schema/constraint validity,
  nonempty admissibility witnesses, and explicit modeled success/failure results.
- Independent native/model comparisons under the pinned SQLite profile for
  empty, singleton and multiple-row histories, NULL TEXT keys where admitted,
  duplicate-value cases allowed by SQLite, and index/constraint preservation.
- Real runner evidence for transaction/rollback and bookkeeping boundaries;
  failed migrations must not acquire a successful verification result.
- Rejections for changed schema/migration/profile, weakened protected meaning,
  omitted fields, unsupported dependencies, unproved premises and untrusted axioms.
- Existing shared checks and platform packaging checks, with bounded timeouts;
  traceability and coverage reflect only the newly established claims.
- Owner review of the concrete pilot contract and final completion evidence.

## Tricky boundaries and relevant code

`SqliteVerifier/{Model,Execution,Preservation,Contract,Library}.lean` currently
describes constraint-free tables and sequential autocommit. Its finite schema
excludes hidden tables. `migration_check/{sql_model,translate,compile,cli}.py`
and the independent checker must agree on any new structural data and profile
semantics. Shared helpers should carry the extension through every
compiler/checker path.

SQLx metadata may have different declared types/defaults from the history table;
its actual pinned source and emitted schema are authoritative. Index namespace,
constraint NULL semantics, row identity, declared-type affinity and failures are
semantic issues, not parser-only relaxations. The existing SQLite grammar parser
already retains unsupported syntax and source spans. Native testing supports
correspondence; it does not prove the SQLite C engine or the SQLx implementation.

The Ultra technical lead owns architecture and integration acceptance. Medium
conformance and integration engineers work in isolated `jj` workspaces, with
independent adversarial review. Progress and validation live in the paired status
file and are updated with each checked commit.
