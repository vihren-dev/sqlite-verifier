# Application-key preservation helpers

Status: IN PROGRESS. Created 2026-10-06.

## Outcome

Library users can choose a logical observation keyed by declared application
columns without retaining physical rowids. Its preservation contract compares
the complete record list with `List.Perm`, retaining coverage and multiplicity.
Row reordering and changed physical rowids satisfy that relation when all keyed
records and protected cells are unchanged. Missing records, extra records and
changed protected values do not satisfy it.

The convenience observation has an explicit domain. Its requested key is
nonempty, its named columns exist, and each observed key is defined, non-NULL
and unique. NULL or duplicate keys produce an absent read or an unsatisfied
domain; no records are silently merged or discarded. Missing requested columns
remain visible even in an empty table. The key's identity is the helper's
documented logical value equality; the helper does not infer SQLite affinity,
collation or native key-constraint truth from tagged values.

The general `Interpretation` and `LogicalContract` constructors remain usable
for other key, NULL, duplicate and ordering policies. Physical-rowid and ordered
projection helpers remain available. Reusable soundness and schema-extension
lemmas establish the new representation and preservation obligations without
changing any existing contract or execution formula. Public declarations,
fields and theorem statements have checked Verso documentation, including
quantifiers, assumptions, empty cases and proof sketches where required.

An approved-example variant verifies `add_column_then_table` through the real
preparation and checker commands using these helpers. Documentation explains
when to choose physical rowids or application keys, and equality or permutation.
No table-rebuild or new SQL statement support is claimed.

Source: [issue #16](https://github.com/vihren-dev/sqlite-verifier/issues/16).
Task card: T15, application-key preservation.

## Acceptance

- Real Lean checks cover row reordering and changed rowids, missing and extra
  records, duplicate records, changed protected cells, NULL keys, duplicate
  keys, missing key/projection columns and the empty-table cases.
- Soundness and schema-extension preservation lemmas compile. Their actual
  assumptions stay explicit, and the general constructors remain accessible.
- The approved-example variant completes preparation and verification with
  the intended status and exit code. The example suite obtains every authored
  role from the selected runtime's shipped example directory. Repeated
  preparation in independent fresh workspaces is deterministic;
  the bundle and trust header bind its exact current inputs and library.
- Relevant source, example, installed-package and ordinary `just test` checks
  pass with their configured bounds. Independent commit reviews pass.
- Existing contract and executor formulas are unchanged. Current callers use
  the single SQL executor from T05; no replaced executor or compatibility alias
  is introduced. The model-package migration can move these application
  helpers later without changing their meaning.

## Constraints and relevant sources

`SqliteVerifier/Library.lean` supplies `LogicalRows`, `Covers`, `observeTable`,
`projectedInterpretation`, its soundness lemma and `TableExtends.project`.
`SqliteVerifier/Contract.lean` supplies the flexible interpretation and logical
contract primitives. T05 consolidates computation conveniences in
`ContractProofs.lean` and guards preservation proofs with `SchemaOnly`.
`SqliteVerifier/Model.lean` stores exact tagged values and ordered physical rows;
its conformance predicate deliberately does not certify native representability.

`examples/approved` and its generated schema binding demonstrate the actual
verification target. The new variant must use the same current binding rules,
rather than rewriting fixed historical upgrade/exporter receipts. Atuin's
history observation is an existing application-specific comparison point.
`SchemaPreservation.lean` preserves user-supplied key meanings through unchanged
projections and does not select a native SQLite comparator.

The approved separate-package work T10 is preferred before final placement,
but is not a prerequisite for these logical helpers. Vocabulary from the
unapproved broad naming issues is not adopted. Files remain below 200 lines.

## Current acceptance boundary

The earlier reviewed helpers and packaged example passed compiler, ordinary and
fresh-archive installed checks on the authorized local Darwin host. Those
receipts describe the retained mixed maintenance history, which also contains
held documentation tooling. They do not establish acceptance of a clean T15
publication change.

The clean change uses the approved T05 implementation at
`8e10a593bf830c272bf6b5e6af525d943ce90212` and contains only this task's helpers,
example, tests and guidance. It retains that base's source, protected baselines,
mutation correction, model timeout and evidence. Held T07 and T18b changes are
excluded. Its clean Darwin compiler, source, ordinary, example and fresh-archive
installed checks now pass and bind checked source `d2d33a6b`. The status file
records the exact inputs, runtime, archive and original receipts. T05 owner
approval is recorded; reviewed CI/release metadata integration, repository
delivery, required hosted checks and T15 delivery remain required. The
acceptance and integration checkpoints require independent review. This task
remains IN PROGRESS; old receipts stay separate from the new checks.
