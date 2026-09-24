# Step 1 formal core status

Created: 2026-09-24. Status: IN PROGRESS — not DONE.

Task: [Step 1 acceptance](20260924-step-1-schema-extensions.task.md).
Source contract: engineering brief revision 0.5 and roadmap proposal v0.1.
Owner: `technical_lead`; challenger: `conformance_review`.
Workspace: `/Users/tzankomatev/work/sqlite-verifier-formal`.
Base revision: `2eb0b74a`; toolchain: Lean `leanprover/lean4:v4.33.0`.

## Checked unit: stored model and ordered execution

- `SqliteVerifier/Model.lean` represents ordinary nullable columns, actual signed
  64-bit rowids, arbitrary tagged stored values, finite exact schemas, and rows.
  Type declarations in this first subset are INTEGER, REAL, TEXT, BLOB, NUMERIC.
  No primary key, NOT NULL, other constraints, defaults, indexes, triggers, or
  rowid-shadowing column declarations are claimed supported.
- `Execution.lean` defines CREATE TABLE and ADD COLUMN, stopping at the first
  modeled statement error. The failure state retains committed earlier changes.
  The executable evaluator and inductive outcome relation are proved equivalent;
  every script has an outcome for every starting database.
- `Preservation.lean` proves every old table, row identity, multiplicity, and old
  cell survives every modeled success or failure. Added cells are NULL. These
  theorems quantify arbitrary databases, not only the regression fixture.
- `Examples.lean` checks multi-statement success, duplicate application values,
  NULL materialization, failure prefixes, missing/duplicate schema names, rowid
  limits, ASCII-only normalization, and the forbidden-name admission rules.

Validation commands use `timeout 30s lean +leanprover/lean4:v4.33.0` for each
module, with preceding compiled modules on `LEAN_PATH`. No SQL axioms,
`sorry`, or native proof-evaluation mechanism were introduced.
After integrating the pinned foundation, `timeout 60s lake build` passed all
seven jobs. The universal execution/preservation proofs report only `propext`,
`Classical.choice`, and `Quot.sound` as foundational axioms.

## Pending integration and review

Independent conformance review reproduced all seven build jobs and found a
missing deterministic SQLite column limit. The model now admits at most 2000
columns and models an ADD beyond that limit as a state-preserving error; boundary
regressions cover the fix. Stored values are explicitly an opaque conservative
superset; Conforms states model-schema validity, not exact native representability.
The reviewer found no further mathematical blocker in the preservation unit.
Follow-up source review aligned ADD error precedence: SQLite checks the column
limit before duplicate names; the model and a combined-failure regression do so.

## General verification contract

`Contract.lean` defines LogicalContract, partial Interpretation, explicit
FailureRepresentation, and the exact VerificationConditions proposition. The
requirements select applicability and allowed failure/change relations. Each
invariant implies schema conformance, definedness, and logical validity; starting
conditions establish the current invariant. A starting witness and total outcome
relation prevent vacuity. Failure readers receive resulting storage, not old-data
copies. `VerificationConditions.of_run` removes inductive-execution boilerplate.
The regression suite proves that contradictory initial conditions cannot satisfy
the generated contract. Conformance review accepted the contract after reproducing
the eight-job build and checking the limit-error correction.

## Public projection library and complete proof

`Library.lean` supplies partial whole-table readers, named-field coverage,
projection invariants, conformance-update lemmas, an empty-state witness, and
named-projection preservation. `Demonstration.lean` proves the complete VC for
adding an invoice note column then creating an audit table. All admitted starting
invoice rows, rowids, and amount values are quantified; the same named projection
is read from actual resulting storage. `timeout 60s lake build` passes ten jobs;
the complete VC theorem uses only propext, Classical.choice, and Quot.sound.

The reader signature alone does not enforce storage provenance: constant or
captured readers remain typeable. This subset independently preserves every old
table/row/cell, and its projection builder reads represented storage with explicit
coverage. A later deleting/rebuilding backend needs stronger provenance/coverage
obligations before claiming the general interpretation restriction is enforced.
Independent review of the new library and complete example is pending.

Generated theorem binding, richer
schema support, native/model correspondence, and independent source/proof review
remain outstanding. The native engine is not proved to implement this model.
Concrete examples are engineering regressions, not real-pilot acceptance evidence.

The lead approved foundation `2eb0b74a` for integration after the coordinator's
independent review and repeated successful Nix checks. The formal branch is
rebased onto it; the public barrel's imports supersede
the foundation's comment-only placeholder.
