# Production-pipeline model conformance status

Created: 2026-09-24. Status: IN PROGRESS.
Parent task: [Step 1](20260924-step-1-schema-extensions.task.md).
Owner: conformance_review. Challenger: technical_lead.
Workspace: sqlite-verifier-parser.
Base merge: native fixtures c62b6d1d, frontend fe5f0ba9, formal library 1f0c28bf.

Outcome: explicitly project-derived, canonical-type examples compare independent
expected rows/schema/errors with pinned native SQLite and kernel-checked Lean
assertions over production parse/translate/sql_inputs output. Preserve old rowids,
values, appended NULLs, statement order, and committed-prefix failures; check
column-limit-before-duplicate precedence.

These examples do not modify or model-check the imported upstream fixture, whose
retained view dependency remains unsupported. Concrete examples are not a proof
of universal native/model refinement. Universal preservation is proved separately.

Tests use bounded parser/native/Lean subprocesses, including source/build profile
checks and independent expected-state assertions. Implementation and checks are recorded below.

Validation passed: `timeout 60s lake build` (10 jobs); pinned-SQLITE3
`python3 tests/conformance_model_test.py` (five independent native/model cases
plus rejected false empty-target equality). Every case uses production parser,
translator, and generated Lean input definitions. The theorem checks use
`decide +kernel`, with no new axioms or native proof evaluation.

Native boundary observations: too-many-columns diagnostic names internal
sqlite_altertab_full; SELECT rowid plus 2000 columns itself exceeds result limits.
The test preserves structured original-table errors and checks the empty maximal
table through exact count plus full column metadata. No guarantee was narrowed.

Changes do not touch upstream imported expectations or their unchecked-model
status. Five project-derived cases are a separate denominator. Independent lead
review and integration remain pending.
