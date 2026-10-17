# Syntax IR around SQL forms (ADR 0013, step 1)

Created 2026-10-17. Status: open.
Status file: [status](20261017-syntax-ir-sql-forms.status.md).
Specification: [ADR 0013](../docs/adr-0013-model-structure.md), decisions D3 and D7,
"Order" step 1. Related: [ADR 0008](../docs/adr-0008-syntax-and-resolution-in-lean.md)
(the Syntax IR this step changes), [ADR 0006](../docs/adr-0006-model-boundary-and-execution-levels.md)
(the rule that D7 reads).

## Pull requests

- **Pull request A (subject):** the IR change in Lean and in the frontend, the resolved
  defaults and cached names in the catalog, the classifiers, the examples and fixtures.
  No change under `judge/` or `integrity/`; `Contract.lean` does not change.
- **Pull request B (judge, owner approval):** only if a verdict changes. One frozen case
  leaves the restriction `boolean-name` (`expr2:expr2-1.4.1:5` of corpus v5) and must
  agree; if it does, PR B adds it to `mustAgree`.

## Outcome

Behaviour does not change except where this list says so: the compiled classifier gives
the same verdict for every case of every frozen corpus except the one named above; every
`#guard` of the `*Examples` files keeps its expected value; `judge/claims.json` and
`integrity/judge.lock.json` change only in PR B.

1. **Calls.** `Syntax.Expr` has `call (name : String) (arguments : List Expr)` and
   `callStar (name : String)`, and no `callEmpty`, `callPair` or `more`. The frontend
   (`belay/sqlite/syntax_queries.py`, `syntax_expressions.py`) emits the list form; the
   JSON operators `->` and `->>` are calls of those names with two arguments. SQLite's
   `wrong number of arguments to function %s()` is one check on the list's length.
   `Resolved.Expr.arguments`, `argumentsOf`, `moreArguments` and `pairIssue` do not exist.
   The resolved side keeps `Resolved.Arguments` (see "Key points").
2. **Comparisons.** `Syntax.Expr.equals` does not exist; `=` is `compare .eq`. Issue paths
   of a comparison's operands are `[1]` and `[2]` for every operator.
3. **Writes.** `Syntax.Write` does not exist. `Statement.insert`, `update` and `delete`
   have a field `returning : List ResultColumn`, empty without `RETURNING`; the resolver
   of each statement resolves its own `RETURNING` at the path of that field, and
   `returningPath`, `returningPaths` and `returningPaths_ok` do not exist.
4. **Quoting.** `Syntax.Expr.identifier` carries `quote : QuoteKind` with `none`,
   `double`, `bracket` and `backtick`. The restriction `boolean-name` leaves the
   registry: an unquoted `TRUE` or `FALSE` that names no column is 1 or 0, and a quoted
   one is `no such column`, as SQLite does. `writtenDefault` decides a text default from
   the quote kind, not from `sourceText`.
5. **Defaults in the catalog.** `CatalogColumn.default : Option ColumnDefault`, where
   `ColumnDefault` is a literal with its insert value and its read-back value (both
   already stored with the column's affinity), or a time keyword, each with the
   `sourceText` that `sqlite_schema` shows. Resolution of CREATE TABLE and ADD COLUMN
   computes it once; `literalDefault`, `writtenDefault`, `readDefaultValue`,
   `CatalogColumn.clockDefault`, `constantDefaultExpression`, `constantDefault` and
   `PrepareError.defaultNotConstant` do not exist, or exist only inside that resolution.
   Execution and the omitted-cell rules read the stored values.
6. **Folded names and affinity in the catalog.** `CatalogObject` and `CatalogColumn`
   store their folded name beside the name as written, and `CatalogColumn` stores its
   affinity. `Catalog.find`, `columnPosition`, `Catalog.supported` and `tablesMatch`
   compare folded names with `==`; `affinityOf` runs at resolution only. Messages use
   the name as written.
7. **Join operators.** `Syntax.Join` carries a parsed operator (kind and `NATURAL` flag);
   `joinOperator` is called once, in the frontend mapping or at the start of resolution,
   not in six places.
8. **Classifiers (D7).** `Resolved.Statement.kind` gives control, definition, write,
   query, prepare error or clocked, and every match that today lists all constructors
   to say "otherwise" uses it (`Laws.nonControl`, `SqlProofs.NoWrites` and
   `ModeledDefinitions`, the forwarding arms of `step`, `literalStep` and `advance`,
   `SchemaScript`, `TransactionSpec`, `StatementClock`). `Expr.any` and `Expr.map` over the
   mutual block replace `callsJson`, `readsClock`, `atClock` and `readsBelow`; `eval`,
   `literal?`, `mayBeText` and `isCondition` stay hand-written.
9. **Fixtures.** The 16 fixtures of `conformance/cases/*.json` and the regression fixture
   carry the new Syntax JSON; `tests/syntax_*_test.py` and the resolution examples state
   the new forms.
10. **Names.** The table-position binder is `table` or `tablePosition` everywhere `at_` is
    today.

## Verification

- `just test-full`, `just test-nix` and `just test-scheduled` pass; every mutant anchor
  that moved is updated, and every mutant is still killed.
- `nix-build integrity/judge.nix -A verdict` gives the counts recorded in the status file,
  plus the one case of outcome 4.
- Frontend tests cover each new form: a call with zero, one, two and three arguments, the
  JSON operators, each quote kind, `RETURNING` on each write, each join operator.
- Lean examples: `Resolution/QueryResolutionExamples.lean` and `Examples.lean` show
  `TRUE` and `[TRUE]`, a three-argument call, and a resolved default of each kind.
- The clean build time and `tests.model` do not go up by more than noise (33 s; 334 s).

## Key points for the implementer

- **Nested `List Expr` on the resolved side.** On Lean 4.34.1 `deriving DecidableEq`
  fails for an inductive with a nested `List Expr` (tested 2026-10-17), and
  well-founded recursion over `attach` does not reduce under `decide`. The Syntax side
  can use `List Expr` because nothing decides equality of Syntax in the kernel (check
  `deriving Repr, FromJson, ToJson, ToExpr` with a spike first); the resolved side keeps
  the mutual `Resolved.Arguments`. The frontend's `argument_rest` and `call_pairs` go.
- **Wire format.** The Syntax JSON is the frontend's output and the fixtures' content, not
  the corpora's. `Codec/Resolution.lean` derives `FromJson`/`ToJson` from constructor
  names, so renaming a constructor renames a JSON key; regenerate the 17 fixtures with
  the frontend and check them in with the change (`tests/conformance_freeze_capture.py`
  and `conformance/cases/` are inputs of `tests.model`).
- **Generated terms.** `examples/*/Generated/*.lean` and `SqlInputs.lean` hold resolved
  terms; the gate re-resolves and compares (`packages/sqlite-verifier/GateInputs.lean`),
  so they must be regenerated, and the example proofs that unfold `Generated.resolved`
  (`script_bound`, `default_value`, `constant_default`) are restated.
- **`PrepareError` arms.** Resolution of a call checks the argument count after it
  resolves the arguments, as SQLite does; keep that order so error precedence matches.
- **Quote kinds and SQLite.** `"x"` is a string when `dqs` is on and no column `x` exists;
  `[x]` and `` `x` `` are always identifiers (`no such column`); `TRUE`/`FALSE` are
  keywords only unquoted. Check each against the native build, including in a `DEFAULT`.
- **Defaults.** `readDefaultValue` and `defaultValue` differ for numeric text in a TEXT
  column (`TEXT DEFAULT 1.50` reads back as `1.50` for old rows but inserts `1.5`):
  `ColumnDefault` must hold both values. `Native.lean:84` of `verifier-conformance`
  compares `sourceText` with `sqlite_schema`; keep it.
- **Mutant anchors.** `conformance/write_mutants.py`, `row_write_mutants.py`,
  `fromless_mutants.py`, `json_*_mutants.py`, `clock_mutants.py` and
  `date_function_mutants.py` anchor lines in `QueryExprs`, `Calls`, `ClockRows`,
  `ClockSubstitution`, `Defaults`; `tests/mutant_guards_test.py` checks the `rule:`
  guards. Every moved line moves its anchor.
- **Scope of this step.** It does not change the stored table, the copied keys, the
  evaluator's fault prediction or the clock design; those are steps 2, 3 and 6. Where a
  classifier touches `StatementClock`, keep the `clocked` arm.
