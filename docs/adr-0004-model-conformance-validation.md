# ADR 0004: Validate the semantic model by differential testing and proven regressions

- Status: Proposed
- Date: 2026-09-29
- Implementation examined: working copy on top of `adce4843`
- Decision owners: formal methods lead for model fidelity and proof policy;
  product owner for the conformance claims made in documentation and releases
- Related: [ADR 0001](adr-0001-pytest-and-nix-ci.md),
  [ADR 0003](adr-0003-agent-proof-preparation.md) and its
  [trust extension](adr-0003-trust-extension.md),
  [research report](../reports/Validating%20a%20Lean%20SQLite%20semantic%20model.md)
- This proposal does not change current behavior, supported SQL, statuses, or
  the trust policy. It adds evidence about the model; it never adds axioms.

## Decision in brief

Approve a bounded prototype, not the whole pipeline:

1. Lean `checkCase` is the single comparison authority. Every tier that compares
   the model with SQLite evaluates it; Python records native traces and prints
   diagnostics but never decides agreement.
2. A persistent-connection native runner supplies the per-statement observation
   boundary, including connection-visible and committed state inside an open
   transaction.
3. Work packages W1–W2 demonstrate both, with measured throughput. W3
   (generation at scale) proceeds only on that evidence.

If W2 cannot demonstrate faithful native observation, the existing conformance
checks (`conformance/model_check.py` and the native fixture runner) remain the
evidence, W3 is not authorized, and the obstacle is recorded in this ADR.

The four-tier pipeline in §4 is the intended destination. Its later tiers are
recorded here so the prototype is built toward them, not approved by this ADR.

## 1. Observed problem

Every `VERIFIED` result is a statement about the Lean model in `SqliteVerifier/`.
Its value to users depends on the model agreeing with the pinned SQLite 3.51.0
engine for every admitted statement. Today that agreement rests on five authored
cases in [conformance-model.md](conformance-model.md), three imported `alter3`
assertions that are not model-checked ([conformance-fixtures.md](conformance-fixtures.md)),
and five requirement-ID traceability entries ([coverage.md](coverage.md)).

That evidence is honest about its scope, but it cannot grow at the rate the
roadmap requires. Step 2 (table rebuilds) and Step 3 (data transformations) add
INSERT…SELECT, DROP, RENAME, constraints, indexes, affinity, and expression
evaluation. Each is a larger opportunity for a silent model/engine divergence
than the current additive subset. Four current mechanisms limit scaling:

- Cases are authored by hand, including their expected values
  (`conformance/model_cases.py`). Nobody writes combinations they did not think of.
- The static Tcl extractor accepts only trivial assertion shapes. It imports 3 of
  59 `alter3.test` call sites; 774 of 1,195 upstream test files use `ifcapable`
  and 389 use `foreach`, so static parsing has a low ceiling.
- Every comparison is a `decide +kernel` proof. A local micro-benchmark measured
  7.6 s and ~840 MB for 500 small theorems, and every model change invalidates
  every generated module. This motivates exploring a compiled runner; it does not
  establish that runner's end-to-end throughput.
- The native runner (`conformance/model_native.py`) pipes a whole migration into a
  terminating `sqlite3 -bail` process, then reopens the database to inspect
  committed results. It cannot observe state after each statement, nor
  connection-visible state while a transaction is open.

## 2. Goals

Find model/engine divergences in the admitted subset before users rely on them,
and keep finding them as the subset grows. Preserve a durable, kernel-checked
record of the behavior the model is pinned to. Make "how much have we checked"
a measurable work list instead of a claim.

Non-goals: verifying SQLite's C source; claiming universal refinement from a
finite corpus; changing the product trust policy; conformance for statements
outside the admitted subset (those remain `UNSUPPORTED`).

## 3. Precedents

The research report surveys prior validations of executable formal models
against real systems. The recurring pattern is a compiled or extracted model run
differentially at scale, with a smaller proven or curated tier:

| Project | Validation | Scale |
| --- | --- | --- |
| Cedar (Lean, AWS) | Lean model compiled and fuzzed against Rust; minimized corpus kept in CI | 6 h per fuzz target; 21 bugs from testing, 4 more from proofs |
| SibylFS (POSIX) | Model as trace-acceptance oracle for generated scripts | 21,070 scripts, 98% model line coverage |
| SQLCert, Guagliardo–Libkin | Extracted/implemented semantics vs. PostgreSQL/Oracle on random queries | 10⁴–10⁵ queries |
| EVMYulLean | Compiled `lake test` over the official test suite | 22,330 of 22,332 tests |

None of them kernel-checks the whole conformance suite.

## 4. Target pipeline

| Tier | Input | Runs | Evidence |
| --- | --- | --- | --- |
| 1. Bulk differential | Generated programs; mined upstream cases | Compiled `checkCase` over native traces | Compiled model agrees on these runs; trusts the Lean compiler |
| 2. Proven regression | Minimized disagreements, requirement-tagged and hand-written cases | `checkCase c = true` by `decide +kernel`, sharded modules | Kernel-checked claim about the model for each case |
| 3. Independent replay | Tier 2 and tier 4 declarations | Independent kernel from the [trust extension](adr-0003-trust-extension.md) | Checker-independent tiers 2 and 4 |
| 4. General laws | Rollback, atomicity, ADD COLUMN preservation | Lean theorems; the same laws also run as native properties | Kernel-checked claim about the model for all inputs |

Tiers 2 and 4 provide kernel-checked claims about the model. Native traces and
native property runs provide the empirical connection to SQLite. Neither kind of
evidence proves universal refinement of SQLite by the model. Tier 3 depends on
ADR 0003's deferred independent-kernel milestone, not on its latency milestone.

### 4.1 One case format and one comparison authority

A case is a versioned JSON record with two separate parts.

- The fixture: the starting schema SQL and a finite typed initial database, that
  is, each table's rows with explicit rowids and typed cells. Fixture
  initialization is not the migration under test. Natively it may use forms
  outside the admitted subset, such as INSERT with an explicit `rowid`, as
  `conformance/model_cases.py` already does for rowids `-4`, `9` and `22`. On the
  model side the initial `Database` is constructed directly from the typed rows,
  and the starting `Schema` comes from the production frontend's
  `starting_schema`, which `SupportedSql` requires.
- The migration: its SQL text and parsed structural statements.

The record also holds the native trace, and optional requirement IDs (`R-…`) and
provenance (generator seed, upstream file and test name). The trace begins with
an observation of the initialized fixture, before any migration statement, then
has one observation per executed statement. It is the expected value, produced
only by the pinned engine.

The comparison authority is one Lean function over decoded cases:

```lean
inductive Verdict where
  | agree
  | disagree (position : Option Nat)  -- none: initial observation differs
  | modelUnsupported

def classifyCase : Case → Verdict
def checkCase (c : Case) : Bool := classifyCase c == .agree
```

`classifyCase` first compares the initial observations, so a fixture that the
two sides constructed differently is a disagreement at no statement position,
not a migration result. It then decides admission, and only for admitted cases
compares the per-statement observations. `modelUnsupported` is therefore never
`agree`, and a tier 2 theorem `checkCase c = true` cannot hold for an unsupported
case; W1 states this as a lemma.

`HARNESS_ERROR` is not a Lean verdict. It covers every failure before a decoded
case reaches `classifyCase`: transport, JSON decoding, fixture initialization,
and native observation, including `SQLITE_BUSY`. The runner reports it and never
calls the checker.

Tier 1 runs `classifyCase` compiled; tier 2 proves `checkCase c = true` by
`decide +kernel`. The compiled runner may also print the model's observations so
Python can show a readable diff for a failing case, but that diff is diagnostic
only. The current generated assertions in `conformance/model_assertions.py`
become instances of this check.

If the compiled and kernel evaluations of the same case disagree, first confirm
that both decoded the same statements and trace. Only then is a compiler or
`implemented_by` inconsistency a candidate explanation; it is not isolated
automatically.

### 4.2 Observation boundary

After each statement, both sides record:

- The outcome: success, or a modeled error mapped to SQLite's primary/extended
  result code. Error message text is not compared.
- The connection-visible schema and rows: supported table declarations in
  `sqlite_schema` name order, and each table's rows ordered by rowid as
  `(rowid, typeof, exact value)`; text and blobs by bytes, reals by their 64-bit
  pattern.
- Whether a transaction is open, and the committed state when one is.

Row observation must respect SQLite's result-column limit: `rowid` plus 2,000
columns cannot be selected at once, so wide tables are read with `PRAGMA
table_info` and column-bounded row queries rather than the count-only shortcut
the current runner uses for the empty 2000-column case.

The native side uses one persistent connection to the Nix-pinned 3.51.0 library,
retaining the existing version, source-ID, compile-option and connection
configuration checks. The binding must run in autocommit mode (Python's
`sqlite3` inserts implicit `BEGIN` statements otherwise) and must load the pinned
library, not the system one. Like the production profile, it stops at the first
statement error. While a transaction is open, a second connection reads the
committed state; `SQLITE_BUSY` or any other failure to observe is a
`HARNESS_ERROR`, never agreement.

On the model side, observation uses the production execution path, not a second
evaluator. The trace folds `advance` (`SqlExecution.lean`) over the script from
`{ database := initial }`, exactly as `runSqlFrom` does. After each `.next state`
it records `state.database` as connection-visible and `state.snapshot` as the
committed state when a transaction is open. A `.halt outcome` ends the trace with
`outcome.database` and `outcome.persistedDatabase`. The legacy `step`/`run`
helpers in `Execution.lean` cover only schema extensions and are not used. A
theorem in W1 states that the trace's final observation equals the observation of
`runSql` on the same input, so tier 2 cases and the verifier describe the same
execution.

`Database` stays `String → Option Table`: the contract proofs in `Contract.lean`
quantify over it, and the current kernel assertions already observe it by name.
Observation enumerates the finite set of table names appearing in the case's
statements plus the names in native `sqlite_schema`; the model cannot create
tables under any other name.

Reported verdicts are `AGREE`, `DISAGREE`, `MODEL_UNSUPPORTED`, and
`HARNESS_ERROR`; the first three are `classifyCase` results. `MODEL_UNSUPPORTED`
never counts as agreement. Admission uses the production checks. SQL that the
Python frontend rejects has no structural statements, so no Lean case exists;
the runner reports `MODEL_UNSUPPORTED` without calling the checker, and no tier 2
theorem can be stated for it. For decoded cases, `classifyCase` evaluates
`SupportedSql` (`schemaAllows`, and `supportedSqlFrom`, which applies
`statementReady` to every reached statement) before comparing executions; a
failure makes the whole case `modelUnsupported`. The modeled `invalidDefinition`
error is also a subset-admission failure, not a SQLite error, and maps to
`modelUnsupported`.

### 4.3 Compiled runner

Add a `lake exe` target that reads case records as JSON lines, decodes the
structural statements into `SqliteVerifier.Statement`, evaluates `checkCase`,
and prints the verdict with optional model observations. The statement encoding
is the versioned structural encoding in ADR 0003's P3 package, so both efforts
share one decoder and its tests. Whichever package lands first defines it; neither
blocks on the other ADR's approval.

### 4.4 Generation (tier 1, conditional on W2)

Generate programs from the model's statement forms and render them to SQL, so
every program is in scope by construction and constructor coverage is directly
measurable. Route every rendered statement back through the production parser
and translator, and reject the run if translation does not reproduce the
generated statement; this also tests parser round-tripping.

Use a Hypothesis `RuleBasedStateMachine` in pytest, with a well-scoped mode and
an error-seeking mode (duplicate names, missing tables, the 2000-column limit,
NOT NULL and uniqueness violations, transaction-state errors). Bias values toward
affinity corner cases (`'1'`, `' 1'`, `'1.0'`, `1e20`, ±0.0, integers at 2⁶³,
empty TEXT vs. empty BLOB, NULL). A fixed-seed bounded run belongs in `just test`
within the existing budgets; long runs are a separate target that never gates
ordinary development. Hypothesis must be added to the pinned Nix environment.

### 4.5 Freezing disagreements as proven regressions

Every confirmed disagreement is minimized (shrinking, then statement deletion
that preserves the same disagreement signature) and classified as model bug,
harness bug, documentation gap, or engine quirk deliberately modeled. After
resolution, the minimized case is committed as a tier 2 theorem with its
classification in a mismatch log next to the fixtures. A disagreement is never
resolved by editing a recorded native trace.

Tier 2 modules hold 100–300 cases each so Lake can build them in parallel. A test
rejects any tier 2 or tier 4 theorem whose axioms include `sorryAx`,
`ofReduceBool`, or a `_native` name. `native_decide` and `decide +native` are
prohibited in all proofs: since Lean 4.29 each use introduces its own axiom.

### 4.6 General laws

For the current subset, prove over `advance` and `runSql`, under `SupportedSql`:

- Rollback: from an idle state, if `S` contains no transaction-control statement
  and every statement of `S` succeeds, then `runSql (BEGIN :: S ++ [ROLLBACK])`
  succeeds with the initial database. `runSql` stops at the first error, so a
  failing `S` never reaches `ROLLBACK`; that case is covered by atomicity instead.
- Statement atomicity: if `advance` halts with a modeled error from state `s`,
  the outcome's connection-visible database is `s.database` and its committed
  database is `s.snapshot`, or `s.database` when no transaction is open. This
  covers DDL, literal writes, and transaction-control errors alike.
- ADD COLUMN preservation: a successful, admitted `ADD COLUMN` step preserves the
  table's row count, rowids and existing cells, and the new column reads NULL.

Each law also runs as a native property under the same preconditions. The list
grows as Step 2 adds rename and copy semantics.

### 4.7 Later: upstream mining and coverage

Replace the bounded static extractor with an execution-based one: run the
`version-3.51.0` Tcl test files under a logging proxy for the Tcl `sqlite3`
command, cut each assertion into the statements since the last reset followed by
the assertion, minimize natively, and record a fresh typed trace. The Tcl
expected list only confirms extraction; it is untyped, and NULL prints as an
empty string. Exclude multi-connection, file-level, user-function,
fault-injection and query-plan tests with a recorded reason.

Regenerate the 3.51.0 requirement list and extend the traceability table into a
matrix over the admitted subset. Public Tcl tests cite none of the requirements
in type affinity (`datatype3`), `lang_transaction`, or `lang_createindex`, and
only 9 of 21 in `lang_altertable`; those cases are written by hand. Measure model
constructor/error/match-arm coverage and gcov branch coverage of a separately
built 3.51.0 limited to functions the subset reaches, as work lists rather than
finish lines.

## 5. Assumptions and limits

- Finite testing cannot establish refinement. Documentation and reports keep
  naming exact denominators, as [coverage.md](coverage.md) does now.
- SQLite behavior that is implementation fact rather than documented semantics,
  such as unordered row order, which of several violations is reported, and rowid
  choice at the maximum rowid, must be either modeled deliberately with a
  mismatch-log entry or excluded from the admitted domain. Observations use
  `ORDER BY rowid`; where order is unspecified, cases also run under
  `PRAGMA reverse_unordered_selects`.
- Tier 1 trusts the Lean compiler, the decoder, and the native harness. That is
  acceptable for finding bugs and unacceptable as proof evidence.
- The string-literal replay issue in comparator (`leanprover/comparator#93`)
  concerns tier 3 and belongs with the trust extension's kernel qualification.

## 6. Alternatives considered

**Prove every case in the kernel.** Rejected as the primary loop: cost scales with
suite size times model changes, and no precedent does it. Kept for tier 2.

**Compare in Python.** Rejected: two comparators could disagree about what
agreement means, and tier 1 results would then say nothing about tier 2.

**Replace `Database` with an association list.** It makes whole-state equality
decidable, but churns every contract proof for no gain in conformance power,
since observation over a finite name set suffices. Revisit if kernel lookup
through nested `Database.set` closures becomes a measured bottleneck.

**Use `native_decide` for bulk tiers.** Rejected: it adds per-use axioms that the
product policy and independent replay cannot accept, and a compiled runner gives
the same speed without pretending to be proof.

**Keep extending the static Tcl extractor.** Rejected: loops, `ifcapable` and Tcl
substitution make static extraction brittle, and it cannot recover typed values.

**Adopt SQLancer or sqllogictest wholesale.** Deferred. SQLancer's oracles compare
SQLite with itself; its generator is a later diversity source filtered through
the production parser. sqllogictest matters for the expression phase.

## 7. Work packages

| Package | Depends on | Completion evidence |
| --- | --- | --- |
| W1: case format, `classifyCase` and `checkCase` | None; shares the ADR 0003 P3 encoding | Five existing cases re-expressed, their fixtures (including rowids `-4`, `9`, `22`, the NULL and UTF-8 cells, and the 2000-column table) surviving serialization and matching the initial native observation; kernel proof and compiled run agree; a deliberately wrong trace is rejected by both; a lemma shows `modelUnsupported` cases never satisfy `checkCase`; the trace's final observation is proved equal to `runSql`'s; axiom test covers `_native` names |
| W2: persistent native runner and compiled runner | W1 | Existing cases agree; an admitted transactional literal write reaches comparison; an error inside an open transaction is observed with connection-visible changes and an unchanged committed snapshot on both sides; a data-domain rejection (`statementReady` false) and `invalidDefinition` yield `MODEL_UNSUPPORTED` before comparison; injected model mutation yields `DISAGREE`; measured cases/second including native snapshots |
| W5: general laws | None | The three §4.6 theorems proved with stated preconditions |
| Decision point | W2 | Owners review W2 evidence and decide whether and at what scale W3 proceeds |
| W3: generator | Decision point | Both modes run in `just test` at a fixed seed within budget; round-trip checked; shrunk failure reproduces; W5 laws run as native properties |
| W4: regression freezing and mismatch log | W3 | Every disagreement classified and, if resolved, committed as a tier 2 theorem |
| W6: upstream extractor | W2; scheduled with Step 2 | Pilot on `alter*`/`altertab*` at 3.51.0 with per-file yield and exclusion reasons |
| W7: requirement matrix and coverage | W2; scheduled with Step 2 | Requirement list regenerated; model and gcov coverage reports produced |

W5 is pure Lean over the model and does not wait for the runner. Each package
follows the repository task/status file process.

## 8. Rollout and rollback

Tiers are additive test infrastructure. Nothing in this ADR changes the CLI,
statuses, or release artifacts. Documentation updates [coverage.md](coverage.md)
and [conformance-model.md](conformance-model.md) with each package, keeping exact
denominators and separating generated-run counts from proven cases. Rollback
removes a tier's test targets; proven cases stay, since they are ordinary Lean
theorems about the model. The existing `model_check.py` comparisons are removed
only after W1 shows the re-expressed cases pass with the same fixtures and
expectations.
