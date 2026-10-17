# Model structure refactor after ADR 0012

Created 2026-10-17. Status: open.
Status file: [status](20261017-model-structure-refactor.status.md).
Related: [ADR 0006](../docs/adr-0006-model-boundary-and-execution-levels.md) (the
execution levels and the rule against catch-all arms), [ADR 0008](../docs/adr-0008-syntax-and-resolution-in-lean.md)
(resolution), [ADR 0012](../docs/adr-0012-query-semantics.md) (the forms that slices 1
to 6g added), and the proposed [ADR 0012 amendment 6](../docs/adr-0012-query-semantics.md),
which decides the two changes that this task does not make.

## Why

Slices 1 to 6g of ADR 0012 added forms to the model without a refactoring pass. A review
on 2026-10-17 of `packages/belay-sqlite` (159 files, 16,199 lines, 871 definitions, 218
theorems; every file under 200 lines; near-total docstrings; no `sorry`) found the code
healthy but the structure costly:

- Adding one `Syntax.Expr` constructor touched 11 files; one `Resolved.Expr`
  constructor touched 10; `Resolved.Statement` has 13 full-list match arms in 7 files that
  each encode one fact (control, definition, write or query).
- About 650 lines in 7 proof files (`OperandIssues`, `IssueLemmas`, `ErrorKinds`,
  `PrepareRules`, `UpdateRules`, `UpsertRules`, `ClockRowRules`) prove one invariant: an
  expression issue never carries a `PrepareError` that names a catalog object. Every new
  resolver needs a new lemma, and `resolveOperand_issue` (81 lines) grows per constructor.
- The import graph is a chain 26 modules deep. `Resolution/` holds the shared IR types,
  the resolver and its proofs; the resolver constant-folds with the evaluator, so 37 of
  65 resolution modules transitively import `QueryEval`. One edge is false:
  `Sources → Writes` exists only for the 3-line helper `issueResolution`.
- `insertReady` and `upsertReady` repeat a block word for word; `Updates` and `Deletes`
  copy the find-table, filter and `RETURNING` scaffolding; `resolveInsert` is an eight-level
  `match` tower where `Queries` uses `do` notation.
- The binder `at_` (112 uses) means a table position, and `position` means a statement
  index in the same signatures. Proof files use ten suffixes (`Laws`, `Spec`, `Rules`,
  `Preservation`, `Proofs`, `Facts`, `Conforms`, `Lemmas`, `Issues`, `ErrorKinds`) with no
  documented meaning.

This task makes the behaviour-preserving changes. It does not change the clock design or
the catch-all rule; those are decisions of amendment 6.

## Observable outcome

Every item below holds with no change to behaviour: the compiled classifier gives the same
verdict for every case of every frozen corpus, `judge/claims.json` and
`integrity/judge.lock.json` do not change, every `#guard` of the `*Examples` files keeps its
expected value, and the public names that `sqlite-verifier`, `verifier-conformance` and the
examples use keep their meaning (a renamed declaration is allowed when every user changes
with it, per the repository's "replaced code" rule).

1. **No false dependency.** `Resolution/Sources.lean` and `Resolution/Queries.lean` do not
   import `Resolution/Writes.lean`; `issueResolution` lives beside `prepareError` and
   `restrict` in `Resolution/Context.lean`; `Resolution/Resolve.lean` imports `Writes`
   directly.
2. **One statement classifier.** A function `Resolved.Statement.kind` (or an equivalent
   name) gives the category of a statement (control, definition, write, query, prepare
   error, clocked), and the places that today list every constructor to say "otherwise"
   use it: `Laws.nonControl`, `SqlProofs.NoWrites`, `SqlProofs.ModeledDefinitions`, the
   forwarding arms of `step`, `literalStep` and `advance`, `SchemaScript`,
   `TransactionSpec`, `StatementClock`. Dispatch on a semantic choice (what `step` does for
   each definition, what `literalStep` does for each write) keeps explicit constructors,
   as ADR 0006 requires. A new `Resolved.Statement` constructor then changes the
   classifier, its semantic dispatch, and nothing else in this package.
3. **Shared write-resolution helpers.** `Resolution/Writes.lean`, `Updates.lean` and
   `Deletes.lean` share helpers for finding the table, resolving an optional filter and
   resolving `RETURNING` at a path; the restriction paths `[1]` to `[4]` are named
   definitions; `resolveInsert` is written with `do` notation. Only `DELETE` checks
   `reservedName` today: the refactor keeps that difference unless native SQLite shows
   the check belongs to the others too, in which case it is a separate, behaviour-changing
   commit with its own cases.
4. **Shared readiness checks.** `LiteralData.insertReady` and `UpsertRun.upsertReady`
   share the "rows stored in the table's form" predicate; INSERT's JSON readiness is a
   named function beside the other `*JsonReady` functions; "no `RETURNING` column calls
   JSON" is one definition.
5. **The issue invariant is in the types.** `PrepareError` is split so that a
   `ValueIssue` can carry only an expression error (no such column, ambiguous column,
   misuse of aggregate, wrong argument count, hex literal too big, and the others that an
   expression gives) and never an error that names a catalog object. `ErrorKinds.namesObject`,
   `IssueLemmas`, `OperandIssues` and the `_issue(s)` lemmas of `UpdateRules`,
   `UpsertRules` and `ClockRowRules` are gone, and the theorems of `PrepareSpec` that used
   them are shorter. The messages (`Messages.lean`) and the wire codec give the same text
   and JSON as before.
6. **Names.** The table-position binder has one name that cannot be confused with the
   statement index (for example `table` or `tablePosition`), used everywhere `at_` is
   today. The proof-file suffixes are reduced to a documented set (for example `Laws` for
   theorems about the executable code, `Spec` for theorems about resolution, `Examples`
   for `#guard` files), recorded in `packages/belay-sqlite/AGENTS.md` or the package
   README, and the files are renamed to fit.
7. **Core count.** `tests/test_model_package.py` states the new core module count, which
   goes down by the deleted lemma files.

## Verification

- `just test-full`, `just test-nix` and `just test-scheduled` pass; the scheduled mutant
  suite shows every mutant still killed (a moved anchor is updated, not dropped).
- `nix-build integrity/judge.nix -A verdict` gives the same counts per corpus as before
  the refactor (recorded in the status file at the start).
- The clean build time of `packages/belay-sqlite` does not go up (33 s wall on
  2026-10-17), and `tests.model` does not go up by more than noise (334 s).
- Each item is its own commit (or a few), each reviewed with `just review`; a review of a
  renaming commit must find no "replaced code" left behind.

## Tricky points

- **Kernel proofs unfold definitions by name.** Proofs in `SqlProofs`, `Laws`,
  `*Preservation`, `UpdateRules`, `PrepareRules`, `WriteCatalog`, `RowSpec` and `QuerySpec`
  use `simp only [resolveUpdate, …]` and `split`; a new helper needs its own unfolding
  lemma or must be added to those `simp` sets. About 170 bare `simp` and 43 `simp_all`
  calls exist; expect some to break on any reordering, and fix them with `simp only`.
- **`Statement.kind` and ADR 0006.** The classifier must not become a catch-all in
  disguise: `step` and `literalStep` keep one explicit arm per constructor they handle,
  and only their "not mine" forwarding uses the classifier. The amendment 6 proposal
  records this reading of the rule.
- **`PrepareError` split and the codec.** `Codec/Resolution.lean` derives `ToExpr` for
  `PrepareError`; `verifier-conformance` maps prepare errors to SQLite primary codes
  (`Case.lean`, `Outputs.lean`) and the judge compares messages. The split must keep the
  JSON and the message text identical; the frozen corpora are the check.
- **Mutant anchors.** `conformance/*_mutants.py` anchor exact source lines in `Writes`,
  `StatementStep`, `LiteralData`, `UpsertRun`, `JsonReady`; `tests/mutant_guards_test.py`
  checks each guard names a declaration of its file. Every moved line moves its anchor.
- **`instrument_model.py` and `tests.nix`** name files of the execution (`Execution`,
  `StatementStep`, `SqlExecution`) explicitly; renamed files are renamed there too.
- **Insert versus upsert.** `.insert` is `.upsert` with no clauses and an all-ABORT
  policy, but has its own execution path and preservation proof. Folding them is out of
  this task (it changes the resolved form); a theorem that relates `insertOutcome` to
  `upsertRun` is welcome if it falls out of item 4.
