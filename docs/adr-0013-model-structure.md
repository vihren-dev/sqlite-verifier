# ADR 0013: Model structure after ADR 0012

Date: 2026-10-17. Status: PROPOSED.
Implementation: [first task](../plans/20261017-syntax-ir-sql-forms.task.md) (step 1);
later steps get their own task files.
Audience: designers and reviewers.
Related: [ADR 0006](adr-0006-model-boundary-and-execution-levels.md) (execution levels,
the rule against catch-all arms), [ADR 0008](adr-0008-syntax-and-resolution-in-lean.md)
(syntax and resolution), [ADR 0012](adr-0012-query-semantics.md) (slices 1 to 6g and
the clock of amendment 5), [ADR 0005](adr-0005-conformance-corpus-scale.md) (the frozen
corpora that check every step).

## Overview

Slices 1 to 6g of ADR 0012 added forms to the model in
[`packages/belay-sqlite`](../packages/belay-sqlite) without a restructuring pass. A
review on 2026-10-17 (first a structural read, then three deep reads of resolution,
execution with its proofs, and values with query evaluation, with measurements) found the
code healthy and the structure costly. This ADR records the causes, decides the new
structure, and orders the work so that each step reduces the next.

The model is healthy by the measures the repository enforces: 159 files, 16,199 lines,
871 definitions and 218 theorems; every file under 200 lines; near-total docstrings;
no `sorry`, `native_decide` or `partial`; hundreds of `#guard` examples checked against
native SQLite; a clean build in 33 s. The cost is in four design choices, described in
"Context". Each new form is a 10 to 16 file change, the proof families grow per form,
and the conformance classifier does the same work three times.

Two facts measured on 2026-10-17 bound the risk of every change here:

- **No resolver theorem is load-bearing.** None of the 83 theorems under
  `Belay/Sqlite/Resolution/` is used outside that directory. The kernel gate re-runs the
  compiled resolver and compares terms (ADR 0008); it does not use these theorems.
- **The frozen corpora do not store the Syntax IR.** Corpus records hold SQL text and
  native observations. Only the 16 fixtures of `conformance/cases/*.json` and one
  regression fixture embed Syntax JSON. Resolution and Syntax can change shape without
  touching a corpus; a step is checked by re-classifying every corpus.

## Context

### The four causes

**1. Schema truth lives in three places that no theorem connects.** The resolver has a
catalog. The database (`Database := Nat → Option Table`, `Model.lean`) stores a
`Table.shape` in every table. Each `INSERT`, `UPDATE` and `UPSERT` statement carries a
copy of the table's keys and conflict policy, taken at resolution
(`Resolution/Resolved.lean`, `Resolution/Writes.lean`). Execution never reads the catalog.
Consequences:

- The conformance classifier (`verifier-conformance/VerifierConformance/Case.lean`)
  resolves the script a second time, statement by statement (`resolveStates`), to know
  which catalog to observe, and runs the script three times: the support check, the
  observation trace and the output trace. Measured on a three-statement case,
  resolution costs 0.4 s of kernel time, resolution with one execution trace 0.4 s, and
  the full classification 1.2 s. The model test suite spends most of its 334 s there.
- Every example proof hand-builds the catalog after each statement (`next_bound`,
  `catalog_bound`, `Conforms.appendAt`, `Conforms.set`).
- A 645-line chain of write-preservation proofs (`AliasPreservation`,
  `UpdatePreservation`, `WritePreservation`, `UpsertPreservation`, `UpsertConforms`,
  `DeletePreservation`) ends in theorems (`literalStep_*_conforms`,
  `checkedWrite_conforms`, `upsertRun_valid`) that no file uses.
- The copied keys are correct today only because no statement that runs can add a key:
  CREATE TABLE must be plain, ADD COLUMN cannot add a key, CREATE INDEX never runs. The
  first keyed statement admitted inside a script would make the copy stale with no
  error.
- The function-typed database derives nothing, so `Outcome` and `SqlState` have no
  `DecidableEq` or `Repr`, and the classifier needs an external bound (`stateBound`) to
  observe it.

**2. Failure is predicted beside evaluation instead of returned by it.** SQLite's
evaluation order (short-circuit `AND` and `OR`, folded constants, a constant `WHERE` term
evaluated once) is not modeled, so the model evaluates a query and separately predicts
whether SQLite reports an error: `Query.fails`, `Expr.mayFail`, `Expr.mustFail`,
`Expr.callsJson` (`JsonFaults.lean`), `queryJsonReady`, `eachJsonReady`
(`JsonReady.lean`). Each prediction re-runs the evaluator; `mayFail` re-applies the JSON
function at every node. A query with JSON calls is evaluated about four times. The
readiness checks of writes (`insertReady`, `updateReady`, `upsertBounded`) run the write
to decide whether it is admitted, and execution runs it again.

**3. The Syntax IR mirrors the parser, not SQL.**

- A function call is five constructors (`callStar`, `callEmpty`, `call`, `callPair`,
  `more`; `Resolution/SyntaxExpr.lean`) that encode an argument list as a binary chain.
  The chain forces the carrier `Resolved.Expr.arguments`, whose docstring says a resolved
  statement never contains it, the helpers `argumentsOf` and `moreArguments`, two issue
  functions, and an arm for each of the five in about 16 exhaustive matches.
- `equals` is separate from `compare .eq`, which costs a `+1` shift of issue paths and a
  duplicate arm in every match.
- `Syntax.Write` duplicates `Statement.insert`, `update` and `delete`, and creates the
  convention "child 4 is RETURNING" with `returningPath` and `returningPaths_ok`.
- `identifier (doubleQuoted : Bool)` loses bracket and backtick quoting. That lost bit is
  the only reason for the restriction `boolean-name` (slice 6e2) and for
  `writtenDefault` reading `sourceText` to find a `[`.
- `CatalogColumn.defaultValue` stores the pre-resolution `Syntax.DefaultExpression`, so
  the kernel-visible database depends on the parser's AST, `readDefaultValue`
  re-evaluates it at every use, and `constantDefaultExpression` with
  `PrepareError.defaultNotConstant` is unreachable from the frontend, which emits only
  six default forms.

**4. The resolver refuses what the evaluator could decide.** `Operand :=
Resolved.Expr × Option Affinity` (`Resolution/QueryAffinity.lean`) exists because
`Resolved.Expr` cannot represent `+x`, which drops affinity. The resolver then refuses
every comparison in which SQLite would convert a value (`textToNumber`, `numberToText`,
`mixedAffinityComparison`) and every bare value used as a condition
(`valueAsCondition`, so `WHERE active` is a restriction). The header of
`Resolution/QueryForm.lean` says the affinity rules are "already applied to literal
operands"; they are refused, not applied. Of the 38 `RestrictionKind` constructors, 8 are
the resolver refusing what the evaluator could do, 5 are SQLite behaviour the model
cannot decide (implementation order), and the rest are scope.

### Smaller findings

- `USING` and `NATURAL` joins are resolved by generating Syntax text (`qualified` names
  and a `coalesce` call) and resolving it again (`Resolution/JoinUsing.lean`,
  `MergedLeft.lean`), so generated conditions inherit the affinity restrictions and get
  paths into text that has no source. `json_each` is a second join algorithm grafted
  after the tables (`Query.functions` beside `Query.joins`, `splitSources`, hidden
  columns), with the restrictions `tableAfterFunction` and `functionJoin` as its
  consequence. Neither representation survives a subquery in `FROM`, which is on the
  roadmap.
- The clock of slice 6e2 is an AST rewrite (`Statement.atClock`) with an `atClock` and a
  `readsClock` for eight node types, a law for each, the carrier `Statement.clocked`
  and the field `clock : Int` of `Resolved.Expr.date`, which resolution sets to 0 and
  execution overwrites.
- Two ports of SQLite's `computeHMS` and time formatting exist (`ClockText.lean` from
  slice 6e2, `Date/DateTime.lean` and `Date/Functions.lean` from slice 6f); two printf
  front ends (`RealText.lean` over `String`, `Date/Printf.lean` over bytes) share one
  digit core; `json_valid` parses its text twice with two grammars
  (`Json/Validity.lean`); `lookupStep` and `locateStep` (`Json/Path.lean`,
  `Json/JsonbOffset.lean`) are twins.
- `Value.real` can hold NaN bits: `IS NULL` says yes (`Comparison.isNull`), `COALESCE`
  says no (`Arithmetic.isNullCell`). The state is unreachable today; the type allows it.
- `normalizeIdentifier` and `affinityOf` (a substring search) run on kernel-visible paths
  at every lookup (`Model.Catalog.supported`, `Catalog.affinity`).
- The rule against catch-all arms (ADR 0006) is applied to every match over a project
  inductive. For semantic dispatch (`step`, `literalStep`, `Expr.eval`) it does what ADR
  0006 intends. For classification ("is this a write", "has this no expressions") it
  restates one fact in 7 to 16 files.
- About 650 lines in seven proof files (`OperandIssues`, `IssueLemmas`, `ErrorKinds`,
  `PrepareRules`, `UpdateRules`, `UpsertRules`, `ClockRowRules`) prove one invariant: an
  expression issue never carries a `PrepareError` that names a catalog object. Every new
  resolver adds a lemma to the family.
- Keywords are written as byte lists (`[97, 117, 116, 111]` for `auto`), and the binder
  `at_` (112 uses) means a table position while `position` means a statement index in
  the same signatures.

## Decision

### D1. Execution carries the catalog

The execution state is a catalog, a concrete list of tables aligned with catalog
positions, and an optional snapshot of both. CREATE TABLE and ADD COLUMN apply the
same catalog functions as the resolver (`Catalog.append`, `Catalog.appendAt`). A write
reads the table's keys and conflict algorithms from the catalog at execution. The
`keys` and `policy` fields leave `Resolved.Statement`, `Table.shape` leaves the stored
table, and `Database` is no longer a function. Conformance observes the state directly;
`resolveStates`, `stateBound` and `observationState` go. The theorem "resolution and
execution agree on the catalog" becomes "both call the same function".

### D2. Evaluation returns its fault

`Resolved.Expr.eval` returns a value and a fault status (`none`, `may`, `must`); a
child's `must` becomes `may` under `AND`, `OR` and `COALESCE`, which SQLite may skip.
`Query.run` returns its rows with the fault of the query, and `step` and the conformance
outputs consume one run. `Query.fails`, `mayFail`, `mustFail`, `callsJson`,
`queryJsonReady` and `eachJsonReady` are removed. A readiness check that computes a
result returns the result, and execution uses it instead of computing it again. The
classifier runs the script once and produces the support verdict, the observation trace
and the outputs from that run (`traceFrom_final` already states the equality for the
trace).

### D3. The Syntax IR follows SQL forms

- A call is `call (name) (arguments : List Expr)`; `callStar name` stays as the distinct
  SQL form `f(*)`. `callEmpty`, `callPair` and `more` go, and with them
  `Resolved.Expr.arguments`, `argumentsOf`, `moreArguments` and `pairIssue`. On Lean
  4.34.1, `deriving DecidableEq` does not accept a nested `List Expr`, so the resolved
  side keeps the mutual `Arguments` list or gets a hand-written instance; the saving is on
  the Syntax side and in the frontend (`belay/sqlite/syntax_queries.py`).
- `equals` merges into `compare .eq`.
- `Syntax.Write` goes; `insert`, `update` and `delete` have a `returning : List
  ResultColumn` field, empty without `RETURNING`.
- `identifier` carries a `QuoteKind` (`none`, `double`, `bracket`, `backtick`). The
  restriction `boolean-name` leaves the registry, and `writtenDefault` reads the kind.
- The catalog stores a resolved `ColumnDefault` (a literal with its stored insert value
  and read-back value, or a time keyword) with its `sourceText`, computed once at CREATE
  TABLE or ADD COLUMN. `literalDefault`, `writtenDefault` and `readDefaultValue` are
  evaluated there and nowhere else. The catalog also stores each column's affinity and
  each object's folded name, so `affinityOf` and `normalizeIdentifier` run once.
- Join operators are parsed once into a kind and a `NATURAL` flag.

### D4. Affinity is applied, not refused

`Resolved.Expr.compare` carries the affinity that SQLite's `sqlite3CompareAffinity`
gives the comparison, and a `noAffinity` node represents `+x`. `Comparison.apply` applies
that affinity with the existing `storeValue` conversions, and a bare value used as a
condition converts text as SQLite's `sqlite3VdbeRealValue` does. `Operand`,
`conversion`, `affinityIssue`, `mayBeText`, `isCondition` and the restrictions
`textToNumber`, `numberToText`, `mixedAffinityComparison` and `valueAsCondition` go.
Because frozen cases that are restricted today become predictions, this step is
measured first: the classifier runs over every corpus with the change, and every new
prediction must agree before the step is committed.

`RestrictionKind` is split into three registries with their own ids: *unsupported*
(scope not yet modeled), *undecided* (SQLite behaviour that depends on implementation
order, which the model does not predict) and *unrepresented* (the IR loses a fact the
evaluator needs). The third registry must shrink with this ADR; a new entry in it needs a
reason in its docstring.

### D5. One source model

`Resolved.Source := table (position) | each (json path : Expr) | subquery (Query)`, and a
query's `FROM` is one list of `(JoinKind, Source, Option Expr)`. One nested-loop join
evaluates every source, correlated for `each` and for a subquery that reads the row.
`EachSource`, `Query.functions`, `splitSources` and the generated-Syntax `USING`
resolution go; `USING` and `NATURAL` build their equalities directly from known
positions. The restrictions `tableAfterFunction`, `functionJoin` and the part of
`duplicateSource` that the generated text needed leave the registry. The `subquery`
constructor is added by this ADR without semantics: its resolver and evaluator come with
the subquery ADR, and until then it is the restriction `subquery` in the *unsupported*
registry. The scope keeps an offset per source instead of recomputing offsets by folds.

### D6. The clock is an evaluation parameter

`Expr.eval`, `Query.run`, `step` and `literalStep` take the statement's clock value;
`runSqlAt` passes `clock position` to each step; `CURRENT_TIME`, `CURRENT_DATE` and
`CURRENT_TIMESTAMP` are `DateFunction.value clock []` of `time`, `date` and `datetime`.
`Statement.clocked`, `ClockCell`, `ClockRows`, `ClockRowRules`, the `atClock` and
`readsClock` families, `StatementClockLaws` and the `clock` field of `Resolved.Expr.date`
go, and `ClockText.lean` keeps only what `Date/` does not have. A `VALUES` item or an
omitted default that reads the clock stays an expression in the resolved row. The lemma
"a script with no clock-reading expression has one outcome for every clock" is proved
once over the evaluator. Owner decision 8 of ADR 0012 (the relation over clock
assignments; `Contract.lean` unchanged) is not affected.

### D7. Explicit arms for dispatch, classifiers for everything else

This is the reading of the ADR 0006 rule. A match that chooses a semantic action for a
constructor (`step`, `literalStep`, `advance`, `Expr.eval`, the resolver of each statement)
lists every constructor it handles and has no catch-all. A match that only classifies
constructors uses one named classifier function (`Resolved.Statement.kind`,
`Syntax.Expr.literal?`, and others as needed) whose definition lists every constructor
and whose docstring states the classification. Catch-all `_` arms over project inductives
stay forbidden, so a new constructor cannot pass unseen. Classifiers and the generic
traversals `Expr.any` and `Expr.map` over the mutual block replace the hand-written
`callsJson`, `readsClock`, `readsBelow` and their twins; `eval`, `literal?`, `mayBeText`
and `isCondition` stay hand-written where D2 and D4 keep them, because they are
semantics.

### D8. Invariants in types, not in lemma families

- `PrepareError` splits into errors that name a catalog object and errors of an
  expression; `ValueIssue` carries only the second. `ErrorKinds.namesObject`,
  `IssueLemmas`, `OperandIssues` and the `_issue(s)` lemmas go. Messages and the wire
  codec give the same text and JSON.
- `Value.real` cannot hold NaN: reals are built only through `realValue`, and `Table.Valid`
  states it. `isNull` and `isNullCell` become one function.
- Proof files use three suffixes: `Laws` for theorems about the executable model, `Spec`
  for theorems about resolution, `Examples` for `#guard` files. The package README
  records the meaning.
- The library states its API lemmas once (`runSqlFrom_cons`, `advance_effect`,
  `effect_createTable_ok`, `effect_addColumn_ok`, `effect_write_ok`, a frame lemma
  "a write to position k leaves position j ≠ k unchanged", and
  `VerificationConditions.ofSchemaProjection` for schema-only scripts). User proofs and
  demonstrations stop unfolding `runSql`, `advance`, `literalStep` and `step`.
- Statement effects are position-free and return `Except`, as ADR 0006 specifies; the
  script-level `Outcome` adds positions. One publication path applies constraint
  checks, the ABORT, FAIL and ROLLBACK algorithms and the transaction state;
  `LiteralData.failedDatabase` goes.

### Order

The steps, with what each deletes and what it depends on. Each step is a task file with
its own pull requests; a step changes no corpus verdict unless its entry says so, and it
is checked by `nix-build integrity/judge.nix -A verdict` against the counts of the step
before it.

| Step | Decision | Deletes | Depends on | Verdicts |
|---|---|---|---|---|
| 1 | D3 Syntax IR, resolved defaults, folded names, cached affinity; D7 classifiers | `arguments`, `more`, `callPair`, `callEmpty`, `Write`, `returningPaths`, `boolean-name`, dead default checks, 13 full-list `Statement` arms | — | unchanged (one case leaves `boolean-name` and must agree) |
| 2 | D1 execution carries the catalog; concrete database | `Table.shape`, copied keys, `resolveStates`, the unused preservation chain, example plumbing | — | unchanged |
| 3 | D2 single-pass evaluation; one classifier pass; readiness returns results | `JsonFaults`, most of `JsonReady`, `Query.fails`, two of three executions | 2 | unchanged |
| 4 | D4 affinity applied; registries split | `Operand`, four restrictions | 1 | restricted cases become predictions; measured first |
| 5 | D5 one source model, direct `USING` | `EachSource`, `splitSources`, generated-Syntax `USING`, two or three restrictions | 1, 4 | restricted cases become predictions |
| 6 | D6 clock parameter; one HMS and printf port | `clocked`, `ClockCell`, `atClock` family, `StatementClockLaws`, `ClockText` duplicates | 2, 3 | unchanged |
| 7 | D8 `PrepareError` split, NaN invariant, suffixes, API lemmas, position-free effects | `_issues` family, `failedDatabase`, example boilerplate | 2 | unchanged |
| 8 | Deduplication: JSON twins, `json_valid` grammar, byte helpers, a byte-string literal macro | about 400 lines | — | unchanged |

Steps 1, 2 and 8 can start at once. Step 7 may be done in parts earlier where a step
touches its files anyway.

## Consequences

- **Cost of a new form.** A new expression form changes its evaluator arm, its resolver
  arm, each classifier and the codec. A new statement form changes its semantic dispatch
  and `Statement.kind`. Neither changes a proof family.
- **Kernel time.** The classifier does one resolution and one execution per case
  (measured: about one third of today's cost on a three-statement case), and strings are
  folded once. The model test suite gets shorter per case; the number of cases keeps
  growing with slices.
- **Verification target.** `Contract.lean` does not change. User proofs get shorter
  through the API lemmas and `ofSchemaProjection`; the examples are rewritten to use
  them.
- **Subqueries.** D5 gives `FROM` one source list with a reserved constructor, so the
  subquery ADR adds a resolver and an evaluator arm instead of a representation.
- **Restrictions.** The *unrepresented* registry makes visible which refusals are the
  model's own limitations. Steps 4 and 5 are the only steps that change verdicts, and
  only from restricted to agreeing.
- **Churn.** Steps 1, 2 and 5 rewrite the generated terms of the examples and the mutant
  anchors of `conformance/*_mutants.py` (about 214 mutants, each an exact text match with
  a `rule:` guard). Every moved line moves its anchor; the scheduled mutant suite is the
  check.
- **ADR 0006 and ADR 0008.** D7 is the reading of ADR 0006's rule and D8 implements its
  position-free effects; D3 changes the Syntax IR that ADR 0008 describes. Both ADRs get
  a pointer to this one when it is accepted.

## Alternatives considered

**Leave the structure and keep adding slices.** Rejected: the cost per form is already
10 to 16 files, and the next ADRs (subqueries, `DISTINCT`, `HAVING`, collations) add
forms to every family at once.

**Only the behaviour-preserving cleanups** (the task file of #158 before this ADR).
Rejected as insufficient: they remove symptoms (the classifier, the lemma family, copied
blocks) and leave the three-way schema truth, the second evaluator and the parser-shaped
IR, which are what grows.

**Resolve lazily at execution** to remove the resolver's catalog state machine. Rejected:
it would put name folding and lookup inside kernel proofs, and the resolver's static
catalog is the right abstraction for a target that quantifies over databases.

**Text as `String`.** Rejected: SQLite text may be invalid UTF-8, and `List UInt8` reduces
in the kernel as well as anything; readability is fixed by a literal macro.

**A nested `List Expr` on the resolved side.** Rejected for now: `deriving DecidableEq`
fails on the pinned toolchain; the mutual `Arguments` list stays until a hand-written
instance is worth its proof.

## Not decided here

- Subquery semantics (resolver and evaluator of `Source.subquery`), compound `SELECT`,
  `DISTINCT`, `HAVING`, window functions.
- Folding `Resolved.Statement.insert` into `upsert` with no clauses, which would remove
  one execution path; a theorem relating the two paths is welcome in step 7.
- Splitting `Resolution/` into directories for the IR, the resolver and its proofs; a
  mechanical change once the steps are done.
- Whether `OutcomeSatisfies` should say something about the persisted half of a pending
  outcome, or forbid error-free pending outcomes in contracts without
  `requiresSuccess`. That is a product decision about the contract, not structure.

## Owner decisions

1. **D1 to D3, D6 to D8.** Proposed 2026-10-17; awaiting the owner. These change no
   corpus verdict.
2. **D4 and D5.** Proposed 2026-10-17; awaiting the owner. These turn restricted cases
   into predictions, so each is measured over every corpus before it is committed, and
   its pull request B lists the newly agreeing cases.
3. **D7 as the reading of ADR 0006.** Proposed 2026-10-17; awaiting the owner. It changes
   a repository rule, not only code.
