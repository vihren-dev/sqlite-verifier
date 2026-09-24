# Step 1: verified SQLite schema extensions

Created: 2026-09-24. Status: OPEN — not implemented.

## Outcome and governing documents

Deliver roadmap Step 1: a usable offline verifier for one SQLite migration
script, checked against reusable human-approved Lean requirements and current
interpretation. A script may contain multiple statements. Completion requires
engineering evidence and a pilot's actual use; neither substitutes for the other.

- [Engineering brief, revision 0.5](../sqlite-migration-verifier-engineering-brief.md)
- [Product roadmap, proposal v0.1](../sqlite-migration-verifier-roadmap.md)
- [Team agreement, version 0.2](../sqlite-migration-verifier-team-guide.md)
- [Progress and decisions](20260924-step-1-schema-extensions.status.md)

## Observable acceptance criteria

The public `migration-check verify` interface accepts all seven inputs specified
in the brief, including the required exact-version execution profile and separate
current/proposed interpretations. It supports human diagnostics and JSON.
Exit zero means the expected obligations for those exact inputs were checked;
project compilation by itself never establishes verification.

The first semantic subset covers ordinary table creation and restricted nullable
column additions. Its precise eligible schemas, SQL definitions, environment
assumptions, and failure/progress guarantees are documented with acceptance
examples. Nonunique indexes are conditional on demonstrated pilot demand.
Unsupported dependencies in the starting schema also block verification.

Users can express resulting-schema requirements and preservation of existing
logical rows and designated values through the public library. General predicates
remain available beneath conveniences. Reusable proofs or proof-producing
automation make recurring supported additions practical. The same approved
requirements work across independently checked migrations.

Generated representations and obligations are inspectable and bind the supplied
SQL, statement order, profile, interpretations, invariants, requirements, and
dependencies. The verifier rejects unfinished proofs, unauthorized axioms, and
unproved extra assumptions. CI identifies and protects the approved baseline,
including transitive dependencies; intentional changes follow human approval.

The parser targets the complete pinned SQLite grammar while reporting semantic
support separately. Scripts preserve source spans and SQL statement boundaries.
Valid syntax with unsupported behavior is reported as `UNSUPPORTED`.

The release distinguishes `VERIFIED`, `VIOLATED`, `UNVERIFIED`, `UNSUPPORTED`, and
`INPUT_ERROR`. A rejected proof is not called a demonstrated violation.
Diagnostics connect requirements, obligations, Lean locations, and relevant SQL
where available. Missing/malformed profiles are input errors; a different version
is unsupported and reports the requested and supported versions.

Version-matched native/model conformance and documentation traceability accompany
supported behavior. Reports separate proof status, semantic support, grammar and
fixture coverage, documented claims, and native/model discrepancies, with explicit
denominators and exclusions. Public fixtures retain their original expectations
and relevant execution context.

A fresh checkout enters the pinned Nix/direnv environment and runs documented
`just` build, test, check, and packaging commands. GitHub Actions uses those same
commands, retains installable artifacts for declared platforms, and smoke-tests
the package. A version tag produces a verified GitHub Release. The repository is
public at `vihren-dev/sqlite-verifier`, uses `jj`, and contains the MIT license and
required third-party notices.

A pilot verifies real schema-extension migrations, adapts the public requirements,
and repairs rejected examples using diagnostics. Record human authoring/review
effort against the previous workflow separately from agent effort. Completion
includes product-owner review and a roadmap update recording evidence,
limitations, and the next decision. Do not mark this task DONE before that review.

## Required verification suite

All executable tests have explicit short timeouts, with bounded longer limits
only for checks that require them.

- End-to-end valid proofs for table creation, nullable-column addition, and a
  multi-statement script, reusing requirements between examples.
- Schema and protected-row/value requirements over arbitrary admitted initial
  states, with explicit applicability and all modeled execution outcomes.
- Failure and successful-prefix cases consistent with the declared execution
  profile; no implicit whole-script atomicity.
- All diagnostic classes, including a validated violation, incomplete proof,
  unsupported existing-schema dependency, and invalid/mismatched profile.
- Rejection of changed SQL/profile/interpretations with stale or mismatched proofs,
  stale generated artifacts,
  weakened approved requirements or imported dependencies, unfinished proofs,
  unauthorized axioms, and unproved new assumptions.
- Parser regressions for quoted names/text, embedded semicolons, trigger bodies,
  successive-statement validation, and valid but unsupported syntax.
- Native/model regressions for relevant SQLite behavior and side effects, using
  independent upstream expectations and the selected native build.
- Adversarial cases for case-insensitive identifier collisions, conditional
  creation against incompatible existing tables, rowid-name shadowing, and a
  later statement failing after an earlier statement succeeds.
- Fresh-environment checks and installation/package smoke tests exercised both
  locally and in CI; release evidence and the pilot acceptance session.

## Constraints and implementation tensions

The repository initially contains only the three design documents; no source,
generated obligations, fixtures, or executable test suite exists yet.

SQLite's prepare API is not a public AST interface. Evaluate tokenizer/Lemon
reuse before choosing the parser; do not replace script parsing with semicolon
splitting. Full grammar compatibility and the initial semantic subset are
separate responsibilities.

Proof validity and fidelity to native SQLite need independent evidence.
Success-only implications cannot establish applicability or failure safety.
Initial conditions must not silently assume final requirements or exclude all
executions. A proposed interpretation cannot hide lost protected records or use
proof-only old data in place of resulting storage.

The exact SQLite release and Lean toolchain are engineering choices to pin and
validate. Installed versions are observations, not approved release pins.
Choose configuration assumptions explicitly, including transaction protocol,
interference, resource failures, and crash exclusions. Material changes to the
promised guarantee require product-owner input.

No migration-history system, certificate management, reverse checking, or
PostgreSQL implementation is part of this step. Ordinary engineering decisions
within the approved contract do not require owner approval.
