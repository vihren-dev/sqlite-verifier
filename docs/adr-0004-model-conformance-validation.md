# ADR 0004: Validate the semantic model by differential testing and proven regressions

- Status: Proposed
- Date: 2026-09-29
- Implementation examined: working copy on top of `adce4843`
- Decision owners: formal methods lead for model fidelity and proof policy;
  product owner for the conformance claims made in documentation and releases
- Related: [ADR 0001](adr-0001-pytest-and-nix-ci.md),
  [ADR 0003](adr-0003-agent-proof-preparation.md),
  [research report](../reports/Validating%20a%20Lean%20SQLite%20semantic%20model.md)
- This proposal does not change current behavior, supported SQL, statuses, or
  the trust policy. It adds evidence about the model; it never adds axioms.

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
than the current additive subset. Three current mechanisms limit scaling:

- Cases are authored by hand, including their expected values
  (`conformance/model_cases.py`). Nobody writes combinations they did not think of.
- The static Tcl extractor accepts only trivial assertion shapes. It imports 3 of
  59 `alter3.test` call sites; 774 of 1,195 upstream test files use `ifcapable`
  and 389 use `foreach`, so static parsing has a low ceiling.
- Every comparison is a `decide +kernel` proof. That is the right evidence to
  keep, but it is the wrong loop for thousands of generated cases: a local
  micro-benchmark measured 7.6 s and ~840 MB for 500 small theorems, and every
  model change invalidates every generated module.

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

## 4. Decision

Adopt a four-tier validation pipeline sharing one case format.

| Tier | Input | Runs | Evidence |
| --- | --- | --- | --- |
| 1. Bulk differential | Generated programs; mined upstream cases | Compiled Lean model vs. native 3.51.0, per statement | Compiled model agrees on these runs; trusts the Lean compiler |
| 2. Proven regression | Minimized disagreements, requirement-tagged and hand-written cases | `decide +kernel` theorems, sharded modules | Kernel-checked model behavior for each case |
| 3. Independent replay | Tier 2 declarations | Second kernel, once ADR 0003 lands | Checker-independent tier 2 |
| 4. General laws | Rollback, atomicity, ADD COLUMN preservation | Lean theorems, also run as properties against SQLite | Holds for all model inputs |

Tier 2 remains the only tier that produces proof evidence. Tier 1 finds
disagreements; it does not certify agreement. Native re-execution, not a Lean
proof, is what ties any expected value to SQLite.

### 4.1 One case format and one check function

A case is a versioned JSON record: SQL text, the parsed structural statements,
the native per-statement trace, and optional requirement IDs (`R-…`) and source
provenance (generator seed, upstream file and test name). The native trace is the
expected value; it is produced only by the pinned engine.

Add a `Bool`-valued `checkCase` in Lean that compares the model's per-statement
observation with the recorded trace. Tier 1 runs it compiled; tier 2 proves
`checkCase c = true` by `decide +kernel`. Both tiers therefore evaluate the same
function, and a disagreement between them isolates a compiler or
`implemented_by` inconsistency instead of a test-encoding difference. The current
generated assertions in `conformance/model_assertions.py` become instances of this
check rather than a separate format.

### 4.2 Observation and comparison

After each statement, record on both sides:

- The outcome: success, or a modeled error mapped to SQLite's primary/extended
  result code. Error message text is not compared.
- The schema: supported table declarations in `sqlite_schema` name order.
- Every table's rows ordered by rowid, as `(rowid, typeof, exact value)`; text and
  blobs by bytes, reals by their 64-bit pattern.
- Whether a transaction is open, and separately the committed state (the existing
  runner already reopens the database for this).

`Database` stays `String → Option Table`. The contract proofs in
`Contract.lean` and the demonstrations quantify over it, and the current kernel
assertions already observe it by name. Observation enumerates the finite set of
table names appearing in the case's statements plus the names in native
`sqlite_schema`; the model cannot create tables under any other name. Replacing
the representation with an association list is recorded as an alternative in §6.

Outcomes fall into four verdicts: `AGREE`, `DISAGREE`, `MODEL_UNSUPPORTED`, and
`HARNESS_ERROR`. `MODEL_UNSUPPORTED` never counts as agreement. The modeled
`invalidDefinition` error is a subset-admission failure, not a SQLite error, and
must map to `MODEL_UNSUPPORTED` in comparisons.

### 4.3 Compiled runner

Add a `lake exe` target that reads case records as JSON lines, decodes the
structural statements into `SqliteVerifier.Statement`, runs the model, and prints
observations as JSON lines. Python performs the native side and the comparison,
reusing the connection configuration, version/source-ID and compile-option
checks in `conformance/model_native.py` and `model_check.py`. The structural
statement encoding should be the versioned format ADR 0003 proposes for passing
frontend results to Lean, so the two efforts share one decoder and its tests.

### 4.4 Generation

Generate programs from the model's statement forms and render them to SQL, so
every program is in scope by construction and constructor coverage is directly
measurable. Route every rendered statement back through the production parser
and translator, and reject the run if translation does not reproduce the
generated statement; this also tests parser round-tripping.

Use a Hypothesis `RuleBasedStateMachine` in pytest. Bundles carry created table
and column names; failing runs shrink to a minimal statement sequence. Run two
modes: a well-scoped mode that mostly produces successful programs, and an
error-seeking mode that targets duplicate names, missing tables, the 2000-column
limit, NOT NULL and uniqueness violations, and transaction-state errors. Bias
values toward affinity corner cases (`'1'`, `' 1'`, `'1.0'`, `1e20`, ±0.0,
integers at 2⁶³, empty TEXT vs. empty BLOB, NULL).

A fixed-seed, bounded run belongs in `just test` within the existing time
budgets. Long runs are a separate nightly or manually dispatched target and never
gate ordinary development.

### 4.5 Freezing disagreements as proven regressions

Every confirmed disagreement is minimized (Hypothesis shrinking, then statement
deletion that preserves the same disagreement signature) and classified as model
bug, harness bug, documentation gap, or engine quirk deliberately modeled. After
resolution, the minimized case is committed as a tier 2 theorem with its
classification. Classifications are recorded in a mismatch log next to the
fixtures; a disagreement is never resolved by editing the recorded native trace.

Tier 2 modules hold 100–300 cases each so Lake can build them in parallel, and a
test rejects any tier 2 theorem whose axioms include `sorryAx`, `ofReduceBool`,
or a `_native` name. `native_decide` and `decide +native` are prohibited in all
tiers' proofs: since Lean 4.29 each use introduces its own axiom.

### 4.6 Mining upstream tests

Replace the bounded static extractor with an execution-based one. Run the
`version-3.51.0` Tcl test files under a proxy for the Tcl `sqlite3` command that
logs each statement, its typed result and result code, and test boundaries
(redefine `do_test`; `do_execsql_test` and `do_catchsql_test` route through it).
A case is the statements on `db` since the last reset or reopen, followed by the
assertion; minimize it natively and record a fresh typed trace. The Tcl expected
list only confirms the extraction: it is untyped, and NULL prints as an empty
string. Exclude multi-connection, file-level, user-function, fault-injection and
query-plan tests, and tag every excluded file with its reason. Existing
`conformance/upstream/` provenance hashing applies to the added files.

Upstream mining becomes most useful when Step 2 begins: the current subset is
narrow, and only a few upstream assertions fall inside it.

### 4.7 Requirement coverage and code coverage

Regenerate the 3.51.0 requirement list (R-IDs are an MD5 of normalized sentences
in the docs source) and extend the traceability table in
[conformance-fixtures.md](conformance-fixtures.md) into a matrix of admitted-subset
requirements and the tier 2 cases citing them. Public Tcl tests cite none of the
requirements in type affinity (`datatype3`), `lang_transaction`, or
`lang_createindex`, and 9 of 21 in `lang_altertable`; these are written by hand.

Measure two kinds of coverage and treat both as work lists, not finish lines:
constructor, error-variant and match-arm coverage of the model reached by tiers
1–2, and gcov branch coverage of a separately built 3.51.0 limited to the C
functions the subset reaches. The coverage build is a test tool only; it never
replaces the pinned production engine.

### 4.8 General laws

Prove, for the current subset: `BEGIN; S; ROLLBACK` restores the prior state; a
statement that fails with a modeled error leaves the state unchanged; ADD COLUMN
preserves row count, rowids and existing cells, with the new column reading
NULL. Run each law as a Hypothesis property against the native engine too. Extend
the list as Step 2 adds rename and copy semantics.

## 5. Assumptions and limits

- Finite testing cannot establish refinement. Documentation and reports keep
  naming exact denominators, as [coverage.md](coverage.md) does now.
- SQLite behavior that is implementation fact rather than documented semantics,
  such as unordered row order, which of several violations is reported, and rowid
  choice at the maximum rowid, must be either modeled deliberately with a
  mismatch-log entry or excluded from the admitted domain. Comparisons use
  `ORDER BY rowid` and, where order is unspecified, also run under
  `PRAGMA reverse_unordered_selects`.
- Tier 1 trusts the Lean compiler and the Python harness. That is acceptable for
  finding bugs and unacceptable as proof evidence, which is why tiers stay separate.
- The Hypothesis dependency must be added to the pinned Nix environment.
- The string-literal replay issue in comparator (`leanprover/comparator#93`)
  affects tier 3; check Nanoda replay of tier 2 early.

## 6. Alternatives considered

**Prove every case in the kernel.** Rejected as the primary loop: cost scales with
suite size times model changes, and no precedent does it. Kept for the curated tier.

**Replace `Database` with an association list.** It makes whole-state equality
decidable, but it churns every contract proof for no gain in conformance power,
since observation over a finite name set already suffices. Revisit if kernel
lookup through nested `Database.set` closures becomes a measured bottleneck.

**Use `native_decide` for bulk tiers.** Rejected: it adds per-use axioms that the
product policy and independent replay cannot accept, and a compiled runner gives
the same speed without pretending to be proof.

**Keep extending the static Tcl extractor.** Rejected: loops, `ifcapable` and Tcl
substitution make static extraction brittle, and it cannot recover typed values.

**Adopt SQLancer or sqllogictest wholesale.** Deferred. SQLancer's oracles compare
SQLite with itself; its SQLite generator is a later diversity source filtered
through the production parser. sqllogictest matters for the expression phase.

## 7. Work packages

| Package | Depends on | Completion evidence |
| --- | --- | --- |
| W1: case format and `checkCase` | None | Five existing cases re-expressed; kernel and `#guard` agree; axiom test covers `_native` names |
| W2: compiled runner and comparator | W1 | Existing cases agree through the runner; injected model mutation produces `DISAGREE`; `invalidDefinition` yields `MODEL_UNSUPPORTED` |
| W3: Hypothesis generator | W2 | Both modes run in `just test` at a fixed seed within budget; parser round-trip checked; shrunk failure reproduces |
| W4: regression freezing and mismatch log | W3 | Every disagreement found by W3 is classified and, if resolved, committed as a tier 2 theorem |
| W5: general laws | W1 | Three theorems proved; matching native properties pass |
| W6: execution-based upstream extractor | W2 | Pilot on `alter*`/`altertab*` at 3.51.0 with per-file yield and exclusion reasons recorded |
| W7: requirement matrix and coverage | W2 | Requirement list regenerated; model and gcov coverage reports produced |

W1–W5 fit the current subset and precede Step 2; W6–W7 are scheduled with Step 2.
Each package follows the repository task/status file process.

## 8. Rollout and rollback

Tiers are additive test infrastructure. Nothing in this ADR changes the CLI,
statuses, or release artifacts. Documentation updates [coverage.md](coverage.md)
and [conformance-model.md](conformance-model.md) with each package, keeping exact
denominators and separating generated-run counts from proven cases. Rollback
removes a tier's test targets; proven regression cases stay, since they are
ordinary Lean theorems about the model.
