# Automated test generation and differential testing for a Lean SQLite model vs. real SQLite 3.51.0

Scope: generators, oracles, reduction, and coverage measurement for checking an executable Lean 4 model of a SQLite subset against the pinned native sqlite3, then turning discrepancies into permanent proven regression tests. Research date: 2026-09-29. A small number of web sources were fetched; details I could not verify are listed under Gaps rather than stated as fact.

## Q1. DBMS testing tools and their oracles: which generate stateful sequences, which support SQLite and are open source?

### Takeaway
SQLancer (MIT, Java) is the most relevant existing tool. It supports SQLite natively and already generates *stateful* programs: schema, then inserts, then indexes, views and options, then queries. Its oracles (PQS, NoREC, TLP, QPG, plus later DQE and CERT) compare the engine against *itself*, so they are metamorphic rather than differential. For a model-vs-engine setup, the parts worth reusing are SQLancer's SQLite *state generator* and its *reducer*. The oracles can be reused as properties to prove about the model. The closest precedents to "formal model as oracle" are the Prolog SQL-semantics conformance tester (19 bugs across MySQL, TiDB, SQLite and DuckDB) and Cedar's Lean-vs-Rust DRT.

### Cited Findings
- SQLancer builds each test in phases: "First, a database schema is created ... Then, data is inserted into these tables, along with creating various other kinds of database states such as indexes, views, or database-specific options." The SQLite binary is bundled as a JAR dependency. SQLite oracles: NoREC, TLP, PQS and QPG (`--qpg-enable`). License: MIT. — [sqlancer/sqlancer GitHub](https://github.com/sqlancer/sqlancer)
- The SQLancer README describes oracles that "need no reference", starting with PQS (OSDI 2020), NoREC (ESEC/FSE 2020) and TLP (OOPSLA 2020), and later DQE, CERT, DQP and CODDTest. It reports hundreds of bugs found in SQLite, DuckDB, ClickHouse, TiDB and CockroachDB. — [sqlancer README](https://github.com/sqlancer/sqlancer/blob/main/README.md)
- **PQS** (Rigger & Su, OSDI 2020) picks a random "pivot row" and synthesizes a query whose predicate must evaluate to TRUE for that row. The oracle checks that the pivot row appears in the result, which means PQS needs its own expression evaluator. It found 121 unique bugs in SQLite, MySQL and PostgreSQL, 96 of them fixed or verified. — [USENIX OSDI'20](https://www.usenix.org/conference/osdi20/presentation/rigger), [ACM DL](https://dl.acm.org/doi/10.5555/3488766.3488804)
- **NoREC** (ESEC/FSE 2020) rewrites an optimizable query (`SELECT ... WHERE p`) into a form the optimizer cannot touch, e.g. evaluating `p` per row in the projection and counting TRUEs, and then compares the two results. It found 159 previously unknown bugs in PostgreSQL, MariaDB, SQLite and CockroachDB (141 fixed). 51 of those were optimization bugs and the rest were error and crash bugs. — [arXiv 2007.08292](https://arxiv.org/pdf/2007.08292)
- **TLP** (OOPSLA 2020) splits a query into three partitions (`p`, `NOT p`, `p IS NULL`) whose UNION ALL must equal the unpartitioned query. It also covers aggregates. It found 175 bugs in MySQL, TiDB, SQLite and CockroachDB (125 fixed), 77 of them logic bugs. — [ACM DL, OOPSLA'20](https://dl.acm.org/doi/abs/10.1145/3428279); [Rigger TLP preprint](https://www.manuelrigger.at/preprints/TLP.pdf)
- **DQE** (Differential Query Execution) runs SELECT, UPDATE and DELETE with the same predicate φ and checks that they agree on which rows are affected. This is directly relevant to a model that already covers UPDATE. — [DBMS fuzzing survey, arXiv 2311.06728](https://arxiv.org/pdf/2311.06728)
- A survey measured PQS on SQLite as having the lowest semantic validity and the fewest valid cases per second, yet the highest bug-detection efficiency: 276 bugs in 240 minutes (these are the survey's own counts). — [DBMS fuzzing survey, arXiv 2311.06728](https://arxiv.org/pdf/2311.06728)
- **QPG** (Ba & Rigger, ICSE 2023) mutates the database state to steer toward diverse query plans. It found 53 unique bugs (28 logic, 25 crash or internal-error) in SQLite, TiDB and CockroachDB, including 3 SQLite bugs that were over six years old. It exercised 4.85–408.48× more unique query plans than naive random generation and 7.46× more than code-coverage guidance. — [arXiv 2312.17510](https://arxiv.org/abs/2312.17510); [ICSE 2023 page](https://conf.researchr.org/details/icse-2023/icse-2023-technical-track/55/Testing-Database-Engines-via-Query-Plan-Guidance)
- **SQLRight** (USENIX Security 2022) combines coverage-guided mutation, validity-oriented mutations and logic oracles. A later paper notes that "code coverage alone was shown to be an imperfect proxy metric for DBMSs and stateful systems in general." — [SQLRight paper](https://www.usenix.org/system/files/sec22-liang.pdf); [QPG paper](https://arxiv.org/html/2312.17510)
- **Squirrel** applies type-based mutations to a syntax-preserving IR. **DynSQL** (USENIX Security 2023) is a *stateful* fuzzer: it collects DBMS state after each statement and uses it to generate the next one. DynSQL was evaluated on 6 DBMSs including SQLite and found 40 unique bugs. **Griffin** (ASE 2022) is grammar-free: it mutates statement *sequences* guided by a metadata graph of which statements create or access which tables and columns. All three mainly target crashes and memory bugs. — [DynSQL, USENIX](https://www.usenix.org/conference/usenixsecurity23/presentation/jiang-zu-ming); [Griffin, ACM](https://dl.acm.org/doi/10.1145/3551349.3560431); [QPG related work](https://arxiv.org/pdf/2312.17510)
- **Formal semantics as the oracle:** "Conformance Testing of Relational DBMS Against SQL Specifications" defines SQL semantics formally, implements them in Prolog, and uses that as the reference for differential testing of MySQL, TiDB, SQLite and DuckDB. It found 19 bugs and 11 inconsistencies (arXiv 2024, revised 2025). This is the closest published analogue to the Lean model vs. SQLite setup. — [arXiv 2406.09469](https://arxiv.org/abs/2406.09469)
- **LLM-based generation:** ShQveL (arXiv 2505.02012, 2025) extends SQLancer++ by having LLMs (GPT-4o) fill "SQL sketches" and folds the resulting features back into the generator. It found 55 unique bugs (50 fixed) in CockroachDB, CrateDB, DuckDB, MonetDB and TiDB. Other recent work uses LLMs to discover test oracles (arXiv 2510.06663, 2025) and to raise coverage (DBTest 2026 workshop paper "Boosting DBMS Test Coverage via LLM-Driven SQL Generation"; DBcover, arXiv 2608.25573). — [ShQveL arXiv](https://arxiv.org/abs/2505.02012); [Oracle discovery with LLMs](https://arxiv.org/html/2510.06663); [DBTest'26](https://dl.acm.org/doi/10.1145/3810991.3811637); [DBcover](https://arxiv.org/pdf/2608.25573)
- **SQLancer++ / "Scaling Automated Database System Testing"** (arXiv 2503.21424, 2025) generalizes SQLancer's generator across many DBMSs. — [arXiv 2503.21424](https://arxiv.org/pdf/2503.21424)
- **DIRT** (arXiv 2604.16373, 2026) builds the random tester *into* the DBMS so that it evolves with the system and avoids false positives while features are incomplete. It found 23 confirmed bugs in Turso (a SQLite-compatible engine) and outperformed SQLancer variants in true-positive rate. — [arXiv 2604.16373](https://arxiv.org/abs/2604.16373)

### Inferences
- Stateful (DDL + DML + query) generators: SQLancer (schema, then data, then queries), DynSQL, Griffin, the Turso simulator (see Q6), and DIRT. SQLsmith and the original PQS-style work focus on queries over a fixed state.
- Most of these tools are built for engine-vs-itself comparison and would need adaptation. Their generators emit SQL far outside the model's subset (joins, views, windows, pragmas). They would need either a subset filter, or a "parse with the production parser; discard if it does not translate to a model term" step. SQLancer's `SQLite3` provider is Java with per-feature toggles, which makes pruning feasible but still a non-trivial fork.
- DIRT's idea of evolving the generator together with an incomplete system maps closely onto a model whose subset grows over time. It argues for a generator whose supported-feature set is declared in the same repo as the model.
- SQLRight, Squirrel and Griffin optimize for crash discovery via C-code coverage. They are low priority here, because the target is semantic disagreement and not crashes.

### Gaps
- I did not fetch primary sources for SQLsmith, Sedar, CERT (cardinality-estimation restriction testing) or DQE bug counts. Their SQLite applicability is taken from the SQLancer README and survey summaries only.
- I could not confirm that SQLancer's current SQLite provider can be restricted to exactly the model's subset without code changes.

## Q2. How to build a subset-restricted generator (Lean Plausible vs. Hypothesis vs. SQLancer)

### Takeaway
The strongest design generates *model AST terms* and pretty-prints them to SQL. Every generated program is then in scope by construction, and constructor coverage can be measured directly. There are two workable ways to do this. Option A is Lean Plausible (`deriving Arbitrary`, plus Chamelean for constrained, well-scoped generation). Option B is Python Hypothesis `RuleBasedStateMachine`, whose statement sequences shrink automatically. Cedar's experience shows that a *type-directed* (schema-aware) generator finds bugs much faster than an unconstrained one. A second generator that is allowed to produce ill-typed or error-producing inputs is still needed to exercise error paths.

### Cited Findings
- Plausible is "a property testing framework for Lean 4 that integrates into the tactic framework". Custom types need `Repr`, `Shrinkable`, and `SampleableExt` or `Arbitrary`. `deriving Arbitrary` (or `deriving instance Arbitrary for T1, ..., Tn`) derives generators, and shrinking via `Shrinkable.shrink` minimizes counterexamples. It runs from `#eval Plausible.Testable.check` as well as via the `plausible` tactic. — [leanprover-community/plausible](https://github.com/leanprover-community/plausible)
- Chamelean extends Plausible to derive generators, enumerators and checkers for *inductive relations*. It provides `Arbitrary` for unconstrained values and `ArbitrarySuchThat` for "constrained generators which only produce random values that satisfy a user-supplied inductive relation". — [ngernest/chamelean](https://github.com/ngernest/chamelean)
- Hypothesis `RuleBasedStateMachine` generates whole sequences of rule invocations. `Bundle`s pass generated values (for example table names) between rules, and `consumes()` removes them (useful for DROP). `@precondition` blocks inapplicable rules, `@invariant` runs after every step, and `@initialize` runs once. On failure, Hypothesis shrinks the *sequence* and prints it as runnable Python steps. — [Hypothesis stateful docs](https://hypothesis.readthedocs.io/en/latest/stateful.html)
- Cedar used two generators. The type-directed one creates schemas, then entity stores conforming to them, then well-formed policies and requests. The non-type-directed one keeps schema compliance but allows ill-typed conditions to exercise error handling. The type-directed generator gave "deeper coverage of core logic and faster bug discovery." — [How We Built Cedar, arXiv 2407.01688](https://arxiv.org/html/2407.01688)
- Cedar's generators only produce syntactically correct ASTs, so malformed policies went untested. Parser coverage was handled separately with roundtrip tests. — [arXiv 2407.01688](https://arxiv.org/html/2407.01688)

### Inferences
- **Option A: generator in Lean (Plausible or Chamelean over the model AST).**
  - Pros:
    - It is the same language as the model, so there is no AST duplication.
    - Generated terms can be fed straight to the model evaluator and printed via a `toSQL` pretty-printer.
    - A roundtrip property `parse (toSQL t) = t` then also tests the production parser.
    - Plausible's derived `Arbitrary` touches every constructor.
    - Chamelean's `ArbitrarySuchThat` could enforce a well-scopedness relation (e.g. "column referenced exists in the current schema"). This keeps sequences meaningful instead of error-dominated.
  - Cons:
    - Plausible is young, and derived generators are naive: uniform over constructors with little stateful awareness. A hand-written `Gen` in a state monad threading the current schema will probably be needed.
    - Running sqlite3 from Lean needs IO or FFI glue, but the user already has a native runner.
- **Option B: Python Hypothesis stateful machine.**
  - Rules: `create_table`, `add_column`, `insert_literal`, `update`, `begin`/`commit`/`rollback`, `select_all`. Bundles hold table and column names.
  - Pros:
    - Excellent sequence shrinking.
    - Mature ecosystem, including the stdlib `sqlite3` module (the pinned 3.51.0 build would have to be loaded instead of Python's bundled one).
    - Easy to drive the Lean executable as a subprocess, for example over JSON lines.
  - Cons:
    - Duplicates the subset definition outside Lean, so the generator can drift from the model.
    - Constructor coverage of the Lean AST is not guaranteed. It can be mitigated by always parsing the output through the production parser into the Lean AST and logging which constructors appear.
- **Option C: adapt SQLancer's SQLite3 generator.**
  - Pros: battle-tested expression generation (affinity, collation, NULL corner cases) that has found many SQLite bugs.
  - Cons: Java; generates far beyond the subset; its oracles assume engine self-comparison.
  - Best used as a *filtered* source: generate, parse with the production parser, and keep only programs that translate to model terms. This catches SQL the hand-written generator's author did not think of.
- **Recommended combination:**
  - A Lean-native, schema-aware generator produces the bulk of the tests, with constructor coverage guaranteed.
  - A Hypothesis front end, or a Lean shrinker, handles sequence minimization.
  - A filtered SQLancer or LLM-sketch stream (ShQveL-style) provides diversity.
  - As in Cedar, keep one "well-scoped" and one "error-seeking" generator mode.

### Gaps
- I did not verify whether Plausible's `deriving Arbitrary` handles mutually recursive or nested inductives, such as expression trees inside statement lists, in current releases. Nor did I verify whether Chamelean is maintained against current Lean toolchains in 2026.

## Q3. Differential testing architecture: oracle direction, state comparison, nondeterminism, "unsupported"

### Takeaway
Treat SQLite 3.51.0 as the ground truth for *behavior*. The model is the object under validation, the reverse of Cedar, where the Lean model was the oracle for Rust. After every statement, compare a canonical dump of the full database state plus the statement's outcome (success, or error code and class). Prior art mostly compares only query results, so dumping the whole state is an adaptation specific to this project, and it is cheap for small random databases.

### Cited Findings
- Cedar's harness calls the Lean models from Rust inside cargo-fuzz (coverage-guided) and flags any disagreement. The median execution time was 6 µs for the Lean authorizer versus 10 µs for Rust. — [arXiv 2407.01688](https://arxiv.org/html/2407.01688)
- The Turso simulator's `--differential` mode "will run the same interaction plan on both Limbo and SQLite, and compare the results. It will also check for any panics or errors in either database." Its property assertions include checking that "select queries should return the same amount of results". — [Turso simulator README](https://github.com/tursodatabase/turso/blob/main/testing/simulator/README.md)
- sqllogictest handles unordered results with sort modes. `rowsort` sorts rendered rows client-side with `strcmp()`. `valuesort` sorts individual values without keeping rows together. Optional labels store a hash of the results so that equivalent queries can be checked against each other. — [sqllogictest docs](https://www.sqlite.org/sqllogictest); [DuckDB result verification](https://duckdb.org/docs/stable/dev/sqllogictest/result_verification)
- The Prolog-semantics conformance work shows that a formal reference can find both real bugs and "inconsistencies" where the spec is unclear or missing (19 bugs, 11 inconsistencies). That is a reminder that some disagreements will be *model* bugs or *spec* ambiguities and need triage, not automatic blame. — [arXiv 2406.09469](https://arxiv.org/abs/2406.09469)

### Inferences (design recommendations; not from a single source)
- **Canonical state dump after each statement.** For every table in `sqlite_schema` (ordered by name):
  - Dump `sql` text, or a normalized form.
  - Dump every row as `(rowid, [typeof(c), quote(c) or hex(c)])`, ordered by rowid.
  - Use `typeof()` to catch affinity and storage-class differences, and `hex()` or `quote()` to get exact bytes for BLOB, TEXT and REAL.
  - Compare REALs by exact bit pattern (e.g. `printf('%!.17g')`, or a hex encoding computed on the host from the C double). Never compare default text rendering.
  - Include transaction state (autocommit on or off) and, where modeled, `PRAGMA schema_version` or `user_version`.
- **Outcome comparison.**
  - Compare the result class (OK, or error) and the *primary* error code (`SQLITE_CONSTRAINT` vs. extended `SQLITE_CONSTRAINT_NOTNULL` / `UNIQUE` / `CHECK` / `PRIMARYKEY`).
  - Decide explicitly whether the model commits to extended codes and message text. Messages are brittle; prefer comparing codes only.
  - Also compare statement atomicity: after an error, the state must equal the state before that statement unless an OR-clause says otherwise.
- **Unordered results.** Compare as multisets (sorted canonical tuples), unless the query has ORDER BY over a total key. Rowid is deterministic for plain `INSERT` into a rowid table (`max(rowid)+1`), but not after `AUTOINCREMENT` edge cases or when rowid reaches its maximum value. Either model this exactly or exclude it from the generator.
- **"Unsupported" outcomes.**
  - Make "model returns Unsupported" a distinct third verdict. It should never count as agreement.
  - If the generator emits only in-subset terms, Unsupported indicates a generator/model mismatch and should fail loudly.
  - For filtered external sources (SQLancer, LLM), count Unsupported for coverage-gap statistics.
- **Pipeline.**
  - Each case is a JSON record: SQL text, parsed Lean term, SQLite trace (per-statement outcome plus state dump), and model trace.
  - Store disagreements, reduce them (Q4), then emit a Lean test file with the SQLite expected output inlined, for example `example : run prog = expected := by decide` or `native_decide`. This becomes a proven regression test. (The file format is a suggestion.)

### Gaps
- I did not find a published tool that compares full-database-state dumps between a formal model and SQLite. This appears to be novel engineering.
- No source was fetched on SQLite's exact REAL-to-text rendering rules in 3.51. Verify against SQLite docs before relying on text comparison.

## Q4. Test-case reduction for SQL

### Takeaway
Use two layers of reduction. First, run statement-level delta debugging with an "interestingness" predicate that asks whether model and SQLite still disagree on this program. Then run AST-level shrinking on the remaining statements. If generation happens in Lean or Hypothesis, generator-level shrinking (Plausible `Shrinkable`, Hypothesis sequence shrinking) gives validity-preserving reduction for free. C-Reduce works as a text-level fallback.

### Cited Findings
- SQLancer has two reducers. The statement reducer uses delta debugging to cut the statement set to a minimal subset that still reproduces the bug. The AST-based reducer is experimental (`--ast-reducer-max-steps`, `--ast-reducer-max-time`). `--use-reducer` enables automatic reduction. — [sqlancer GitHub](https://github.com/sqlancer/sqlancer); [GSoC 2023 report on SQLancer reducers](https://gist.github.com/ColinYoungTaro/df271b8683b526a6a73b568ce721b5e2)
- Delta debugging (Hildebrandt & Zeller, 2000) greedily removes chunks, shrinking the chunk size until no single unit can be removed without losing the property. — [Probabilistic DD paper, arXiv 2408.04735](https://arxiv.org/pdf/2408.04735)
- C-Reduce (Regehr et al., PLDI 2012) is a generic fixpoint over modular transformations. Its outputs are on average more than 25× smaller than other reducers'. It is language-agnostic enough to run on non-C text via its line and token passes. — [Test-case reduction for C compiler bugs](https://www.cs.tufts.edu/comp/150FP/archive/john-regehr/reducing-c.pdf); [Design and Evolution of C-Reduce](https://blog.regehr.org/archives/1678)
- "Validity-Preserving Delta Debugging via Generator Trace Reduction" (arXiv 2402.04623) reduces the *generator's random choices* rather than the output text, so every reduced candidate is still valid. This is the same principle as Hypothesis's internal shrinking. — [arXiv 2402.04623](https://arxiv.org/pdf/2402.04623)
- Hypothesis shrinks failing stateful runs to a minimal rule sequence and prints them as reproducible code. — [Hypothesis stateful docs](https://hypothesis.readthedocs.io/en/latest/stateful.html)

### Inferences
- Interestingness predicate: `parse(sql) succeeds ∧ in_subset ∧ model_trace ≠ sqlite_trace`, and ideally the *same* disagreement signature (same statement kind and same diff category), to avoid "slippage" onto a different bug.
- Generator-trace reduction is best for Lean-generated or Hypothesis-generated cases. For externally sourced SQL (SQLancer, LLM), parse into the Lean AST and use a Lean-side shrinker over the term, or fall back to SQLancer's statement reducer or C-Reduce on text.
- Reduced cases should be normalized (renamed identifiers `t0`, `c0`, ...) before being frozen as Lean regression tests. This deduplicates them and keeps the files readable.

### Gaps
- I did not verify whether C-Reduce has published SQL-specific passes or documented SQL case studies. Its applicability to SQL here is an inference from its generic passes.

## Q5. Coverage measurement: Lean model, SQLite C code, requirements; mutation testing

### Takeaway
SQLite's own gcov-based 100% branch/MC/DC methodology can be reused on a coverage build of the pinned 3.51.0. The practical approach is to measure branch coverage restricted to the files and functions relevant to the subset (alter.c, insert.c, build.c, update.c, the relevant vdbe.c opcodes, expression affinity and comparison code), and to treat the remaining uncovered branches as a work list. I found no established Lean 4 code-coverage tool. Constructor and branch coverage of the model has to be home-built, for example by instrumenting the evaluator or logging which AST constructors and evaluation rules fire. Mutation testing of the model is also DIY, but it is the best measure of suite strength.

### Cited Findings
- SQLite measures "100% branch test coverage" with gcov `-b`, compiling with `-g -fprofile-arcs -ftest-coverage`. `ALWAYS()` and `NEVER()` become constants during coverage builds so that defensive branches do not count. The code contains 1184 `testcase()` macros to force both outcomes of boundary conditions, giving MC/DC in addition to branch coverage. — [SQLite: How SQLite Is Tested](https://sqlite.org/testing.html)
- SQLite's mutation testing rewrites each branch instruction in the assembly into an unconditional jump or a no-op, recompiles, and confirms that the tests detect the change. Performance-only branches are annotated `/*OPTIMIZATION-IF-TRUE*/` to exclude false positives. — [sqlite.org/testing.html](https://sqlite.org/testing.html)
- SQLite's test assets: TCL tests (51,445 distinct cases); TH3 (proprietary, 100% MC/DC); SLT (7.2 million queries cross-checked against PostgreSQL, MySQL, SQL Server and Oracle); and dbsqlfuzz (proprietary libFuzzer mutating SQL and database file together, about 500 million cases per day). — [sqlite.org/testing.html](https://sqlite.org/testing.html)
- Code coverage is an imperfect proxy for stateful DBMSs. QPG's query-plan coverage found 7.46× more unique plans than code-coverage guidance. — [QPG paper](https://arxiv.org/abs/2312.17510); [QPG HTML](https://arxiv.org/html/2312.17510)
- Cedar noted that a validator non-termination bug escaped DRT because "the probability of generating inputs triggering this bug is extremely low". Random testing plus coverage does not guarantee completeness. — [arXiv 2407.01688](https://arxiv.org/html/2407.01688)
- A Lean Zulip and web search found no dedicated Lean 4 coverage or mutation-testing tool. Lean compiles to C with a stable ABI, which suggests that C-level coverage of the compiled model is technically possible. — [Zulip: controlling compiled C code](https://leanprover-community.github.io/archive/stream/270676-lean4/topic/controlling.20compiled.20C.20code.html)

### Inferences
- **(a) Lean model coverage.** Three options, cheapest first:
  1. Log constructors: have the generator or harness record which AST constructors and which error variants appear per run. This is cheap and gives "every constructor exercised N times".
  2. Rule coverage: thread a coverage-trace writer monad, or `dbg_trace`-style counters, through the evaluator's match arms. This is the most semantically meaningful option.
  3. Compile the model to C and build with `-fprofile-arcs`/`llvm-cov`. This gives branch coverage over the generated C, but mapping it back to Lean source lines is lossy. (This option is untested.)
- **(b) SQLite C coverage.**
  - Build the pinned amalgamation, or better the split sources for per-file reports, with `--coverage` or clang `-fprofile-instr-generate -fcoverage-mapping`. Define `SQLITE_COVERAGE_TEST` so that `ALWAYS`/`NEVER` fold, as SQLite does.
  - Run the suite, then report per-function branch coverage for `sqlite3AlterFinishAddColumn`, `sqlite3Insert`, `sqlite3Update`, `sqlite3CreateTable`/`sqlite3EndTable`, affinity and compare helpers, and the VDBE opcodes the subset reaches.
  - An uncovered branch in a subset-relevant function is either a missing test or a sign that the model lacks a case.
- **(c) Requirement coverage.** SQLite docs carry requirement tags (H-numbers or R-numbers in the evidence-marked docs). A mapping of tag to Lean theorem or test would give a spec-traceability metric. I did not fetch a source confirming the current tag format (see Gaps).
- **Mutation testing of the model.**
  - Write a script that applies source mutations to the Lean evaluator: swap comparison operators, drop a constraint check, flip NULL handling, change the affinity table. Rebuild each mutant and run the differential suite plus the proven regression tests. The kill rate measures suite strength.
  - Proofs themselves may "kill" mutants by failing to compile. Record those separately, since they show which behavior is pinned by theorems and which only by tests.

### Gaps
- I found no evidence of a maintained Lean 4 coverage or mutation-testing tool as of 2025–2026, so this is reported as absent, not as confirmed nonexistent.
- I did not verify the current format and extraction tooling for SQLite "requirements" (evidence marks in docs) in the 3.51 docs.

## Q6. Metamorphic / property-based validation without expected values, and case studies at scale

### Takeaway
SQLancer's oracles are metamorphic laws, and this project can use them twice: *prove* each law as a Lean theorem about the model, and *test* it on SQLite. Useful laws for the current subset include TLP partitioning, NoREC equivalence, DQE agreement between SELECT/UPDATE/DELETE, rollback restoring state, ADD COLUMN preserving rows, and statement atomicity on constraint error. Cedar (25 bugs, 21 of them from differential or property testing), Turso (a differential simulator against SQLite, plus DIRT with 23 bugs) and DuckDB's reuse of SQLite's SLT are the main precedents for doing this at scale.

### Cited Findings
- TLP law: `Q = Q_{p} ⊎ Q_{¬p} ⊎ Q_{p IS NULL}`, which holds because SQL uses three-valued logic. It detects bugs including aggregate bugs. — [OOPSLA'20 TLP](https://dl.acm.org/doi/abs/10.1145/3428279)
- NoREC law: `|SELECT * FROM t WHERE p|` equals the count of rows where `p` evaluates to TRUE, computed without the optimizer. — [arXiv 2007.08292](https://arxiv.org/pdf/2007.08292)
- DQE law: SELECT, UPDATE and DELETE with the same predicate must touch the same row set. — [survey arXiv 2311.06728](https://arxiv.org/pdf/2311.06728)
- Turso simulator properties include Insert-Select ("an inserted row must appear in subsequent select query results matching that row's predicates"). Plans are driven by a random workload distribution, and the deterministic simulation is reproducible from a seed. — [Turso simulator README](https://github.com/tursodatabase/turso/blob/main/testing/simulator/README.md); [Introducing Limbo](https://turso.tech/blog/introducing-limbo-a-complete-rewrite-of-sqlite-in-rust)
- Turso also runs a "Differential Fuzzer" comparing SQL execution results between Turso and SQLite, and publicly files "Differential divergence" issues (e.g. #9162, QUOTE() truthiness in WHERE). — [turso differential-fuzzer skill](https://www.skills.sh/tursodatabase/turso/differential-fuzzer); [turso issue #9162](https://github.com/tursodatabase/turso/issues/9162)
- **Cedar DRT at scale:**
  - Each target is fuzzed for 6 hours on 4 vCPUs / 8 GB, generating millions of inputs.
  - 25 bugs in total: 4 from proofs and 21 from differential or property testing. The 21 break down as 6 from ABAC type-directed authorizer testing, 4 from validator parity, 6 from parser roundtrip, 2 from formatter roundtrip, and 3 from validation soundness.
  - — [How We Built Cedar, arXiv 2407.01688](https://arxiv.org/html/2407.01688); [Amazon Science blog](https://www.amazon.science/blog/how-we-built-cedar-with-automated-reasoning-and-differential-testing); [Lean use case: Cedar](https://lean-lang.org/use-cases/cedar/)
  - A later Kani paper notes that a Cedar bug (multibyte string slicing panic in `contains_at_least_two`) survived Cedar's differential testing against the formal model. — [Kani, arXiv 2607.01504](https://arxiv.org/html/2607.01504)
- DuckDB uses an extended version of SQLite's sqllogictest suite and format. — [DuckDB sqllogictest intro](https://duckdb.org/docs/lts/dev/sqllogictest/intro); [Understanding and Reusing Test Suites Across Database Systems, arXiv 2410.21731](https://arxiv.org/html/2410.21731v1)

### Inferences
- **Candidate laws, provable in Lean and testable on SQLite, for the current and next subset:**
  1. `BEGIN; S; ROLLBACK` leaves the state unchanged, for any in-subset S.
  2. A failing statement (constraint error, default ABORT) leaves the state equal to the pre-statement state.
  3. `ALTER TABLE t ADD COLUMN c DEFAULT d` preserves the row count and rowids and projects old columns unchanged; the new column reads as `d`, or NULL if there is no default.
  4. `INSERT ... SELECT` from `t` into an empty clone equals copying `t` (next subset).
  5. TLP and NoREC over WHERE with typed expressions, once expression evaluation lands.
  6. Commutativity of independent INSERTs into different tables.
  7. `RENAME` followed by the inverse RENAME is the identity on data (next subset).
- Each law is a Lean theorem over the model *and* a Hypothesis or Lean property run against SQLite. A law that fails on SQLite reveals a wrong assumption. It does not indicate a SQLite bug, since SQLite is ground truth.
- The SLT corpus (7.2M queries), and its DuckDB-extended fork, could be mined: filter it to the in-subset statements with the production parser and use it as a free seed corpus. Most SLT queries are SELECT-heavy with joins, so the yield for the current DDL/DML subset will be low.
- Cedar's lesson: parser and pretty-printer roundtrip tests found as many bugs (6+2) as the core authorizer DRT. Add `parse ∘ toSQL = id` for the Lean AST, plus `toSQL ∘ parse` normalization, as a cheap parallel suite.
- Cedar and Kani's lesson: rare-input bugs (non-termination, byte-level string edge cases) evade random DRT. Complement random generation with targeted enumerators for boundary values: max rowid, empty strings, BLOB vs TEXT with the same bytes, NaN and ±0.0 REALs, and integers at the 2^63 boundaries.

### Gaps
- I found no public numbers on the bugs found by Turso's `--differential` simulator mode specifically, as opposed to DIRT's 23.
- I did not verify whether Turso's simulator shrinks failing interaction plans.
