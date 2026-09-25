# Restore the SQL-only product boundary

Created: 2026-09-25. Status: IN PROGRESS.

## Required outcome

The verifier accepts schema SQL, migration SQL, approved Lean requirements and
interpretation, proposed resulting interpretation and proofs, and SQLite semantic
settings. It does not integrate with ORMs or migration frameworks. Profiles must
not contain application migration identities, catalogs or bookkeeping policies.
All database operations claimed by a proof must be represented by the supplied
SQL; framework effects must not be silently added by the engine selection.

The Atuin example is a small, source-justified example at a pinned upstream
revision. Its README links to the relevant upstream schema, migration and
application code and explains its logical requirements, observations, assumptions
and limits. A reasonable schema.sql and an explicit migration.sql represent the
selected migration's database effects. Any bookkeeping or transaction operations
included in the claim are ordinary SQL with generic semantics. Runtime-generated
values must be explained honestly; the example does not certify a live framework
invocation or every possible application execution. No upstream application import,
Rust runner capture, framework integration or certification pipeline is required.

Retain useful reusable SQLite semantics, parser support, proof checking and native
SQL conformance. Remove framework-specific core definitions, frontend policy,
capture dependencies and obsolete evidence/documentation. Existing core examples
and protected-input checks continue to work. Requirements express the actual
application meaning rather than merely restating the candidate SQL.

## Verification

Bounded checks cover ordinary supported SQL and failures, generated-input binding,
kernel rejection of unfinished/substituted proofs, existing examples and the
revised Atuin example. Native SQLite execution of the supplied example SQL checks
schema and data effects on empty and populated histories. Atuin negative cases
must detect lost protected data, incorrect shell initialization and weakened
interpretation assumptions. The normal aggregate suite runs without Rust, Cargo,
application source downloads or framework capture. Documentation links resolve.

## Relevant constraints

RunnerProfile/RunnerExecution/RunnerFootprint currently mix SQLite settings,
SQLx state predicates and implicit database writes. migration_check/profiles.py
and sql_model.py reproduce this coupling. Contract.lean and the trusted proof
gate must remain bound to the actual supplied SQL and assumptions during removal.
Transactions and bookkeeping cannot be deleted from an equivalence claim merely
because the present SQL subset cannot express them: either implement the needed
generic SQL or expose a real unresolved scope question to the owner. Preserve the
small Nix source boundary and resource safeguards from the development repair.

This owner instruction supersedes the earlier Atuin runner-capture and
certification acceptance requirements. It does not authorize a protected-branch
admin bypass or imply final owner acceptance of the revised application contract.
