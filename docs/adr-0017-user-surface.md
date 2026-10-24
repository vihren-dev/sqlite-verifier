# ADR 0017: The user surface, from SQL text to proved claims

Date: 2026-10-20. Status: ACCEPTED on 2026-10-20 (owner decisions below).
Implementation: slice by slice, each with its own task file; ADR 0016 takes effect with
the first slice.
Audience: designers and reviewers.
Related: [ADR 0016](adr-0016-model-and-surface.md) (the surface package, its names and
its layer rules), [ADR 0012](adr-0012-query-semantics.md) and
[ADR 0015](adr-0015-functions.md) (the model's queries and functions),
[ADR 0011](adr-0011-product-trust-and-development-integrity.md) (the judge). The target
user guide, the model comparison, the verification systems review and the SQL pain
points research are in the product repository.

## Overview

The surface is the library that users import, `Belay` with SQLite under `Belay.Sqlite`
(ADR 0016). The target user guide describes its full experience: SQL in Lean source
parsed at elaboration, scripts and programs, queries as propositions, four levels of
assurance, triples, equivalence, counterexamples and automation. The guide is the
target, not a plan. This ADR decides the path to it:

- the order of the slices, by risk and by what a user can do after each slice;
- the first two slices in detail;
- which model work the surface waits for, because the guide's claims need SQL that the
  model does not describe yet;
- the rules that hold for every slice: the surface never approximates, and elaboration
  is outside the trusted base.

## Context

Measured on `main` after ADR 0015 (2026-10-20):

- **What the model already gives a surface.** `Database` (a catalog and rows, with the
  invariant `Database.Valid` as a separate proposition), the model's syntax
  (`Syntax.Statement`), the resolver (`resolve` in `Resolution/Resolve.lean`), the
  resolved statements, and `runSql` over them. The kernel reduces all of it: every case
  of the frozen corpora that agrees, 2,045 of corpus v5 and all of the authored corpora,
  is a proof by `decide +kernel` over these definitions.
- **How SQL text reaches the model today.** The C parser library
  (`parser/library.h`, `sqlite_verifier_parser_parse`) gives a parse tree; a Python
  translation of 1,480 lines (`belay/sqlite/syntax*.py`, `sql_tree.py`,
  `parser_library.py`, `located.py`) turns it into the model's syntax, as JSON that the
  Lean codec reads (`Codec/Resolution.lean`, derived `FromJson`). No Lean code calls
  native code.
- **The guide's claims need SQL that the model does not describe.** The guide states a
  fact as a query, and most of its facts are `NOT EXISTS` subqueries. Its lead examples,
  ranked by the SQL pain points research, need enforced foreign keys with
  `ON DELETE CASCADE` (the rebuild that cascades), triggers (expand/contract), `NOT IN`,
  `HAVING`, `BETWEEN` and `||`. The model has none of these (`docs/semantic-subset.md`).
  The out-of-scope cases of corpus v5 point the same way: triggers mark 416 of them,
  subqueries 332, `DISTINCT` or `HAVING` 185, `||` 105, `BETWEEN` 84, `IN (...)` 39
  (`experiments/functions/measure.py`, 2026-10-20).
- **The product's next milestone** is a public launch that makes readers say "wow"
  (product vision). The research recommends that each example show a false claim with
  its counterexample first, and the proof second.

## Decision

### D1. The slices, in order

Each slice is core work: it gives users something that the goal needs. Each has its own
task file, and each ends with users able to do more than before.

| Slice | What a user can do after it | Guide sections |
| --- | --- | --- |
| S1. SQL text in Lean | Nothing new yet: the elaborator turns SQL text into the model's syntax, in the Lean process and in the editor | "Writing SQL in Lean files" (first part); open questions 8 and 9 |
| S2. Concrete databases | Build a database with `db!`, write scripts with `sql`, run them with `db.run`, see results with `#eval` and `#sql`, and prove facts about one database with `decide`; SQL that does not parse is an error at its position, `sql!` and `db!` also report resolution errors there, and `sql` resolves when it runs; a `Database` carries its validity, and `Holds`, `Empty` and `Fails` hold or fail for one database by `decide` (amended 2026-10-22, D3) | "A first example", "Values", "Databases", "Scripts", "Row order", and the examples of "Queries as propositions" over one database |
| S3. Parameters and programs | Scripts with `$x` and `:name`; programs in `do` notation with `send`, `query`, `single`; `Run`; `Env` with a clock (amended 2026-10-22, D3) | "Parameters", "Programs", "The execution environment" |
| S4. Claims over every database | `Holds`, `Empty` and `Fails` over every database; level 2 (`succeeds where`) with the lemma library | "Queries as propositions", "Level 2" |
| S5. Counterexamples | `#sql_check` and `sql_refute`: a search over small databases whose witness the kernel checks, shown as a script that `sqlite3` replays | "Check before you prove", "Counterexamples for any statement" |
| S6. Triples and equivalence | Triples from `Std.Do`, `≈` and its patterns, level 3 | "Level 3"; open questions 2, 11 and 12 |
| S7. SQL files | `sql_file`, `sql_module`, `against :=`, and the check tool | "SQL in separate files" |
| S8. The whole application | `simulates`, level 4 | "Level 4" |

The order follows three rules. Risk first: S1 is the step that nobody has tried, and
every later slice needs it. A usable result early: S2 is the guide's first example, and
it needs no new model semantics apart from `Output.oneOf`, whose examples wait (D3). Counterexamples before triples: the model comparison
names the learning curve as the main risk of the design, and the verification systems
review shows that a cheap first answer is what makes people adopt a verifier, so S5
comes before S6.

### D2. S1: SQL text in Lean, measured before it is built

S1 starts with two prototypes, each with a measurement that decides it:

1. **The parser in the Lean process** (guide question 8). Load the parser library into
   the elaborator, in `lean` and in the editor's server, through Lean's foreign function
   interface. Measure: that it loads on Linux and macOS in the pinned Lean release, the
   time to parse the texts of the frozen corpora, and what happens to the editor when
   the library is missing.
2. **The translation in the elaborator** (guide question 9). Two candidates: a Lean
   port of the Python translation, or the translation moved into the C library so that
   it gives the model's syntax as the JSON that the codec already reads. Measure, for each: the share of the frozen
   corpora's texts whose syntax equals what the Python translation gives (the
   acceptance bar is all of them), and the size of the code that would then exist twice.

The owner chooses between the candidates after the measurement. Whichever is chosen,
the Python translation is then replaced, not kept beside it, as the repository's rule
for replaced code requires; the conformance harness keeps working because it reads the
same syntax.

Amended 2026-10-21: the owner chose candidate A, the Lean port. The port and the parser binding
move from the surface to a package below it (ADR 0016, D2, amended), and a translation program of
that package translates for the CLI and the harness, so Python no longer loads the parser
library. Installing the surface for Lean users, with its native library, stays with the first
release of the surface (ADR 0016, "Deferred"). Task:
[`plans/20261021-sql-text-package.task.md`](../plans/20261021-sql-text-package.task.md).
Amended again 2026-10-21 ([ADR 0021](adr-0021-remove-the-verifier-product.md)): the CLI was
removed with the verifier product, so the translation program translates for the harness only.

### D3. S2: concrete databases

S2 delivers the guide's first example and its reference rows for `Value`, `Database`,
`Script`, `Output`, `db!`, `sql`, `sql!`, `++`, `db.run` and `#sql`, over the model's
semantics. As the guide says, `sql` parses at elaboration and resolves each statement
against the database when it runs; `sql!` and `db!` also resolve at elaboration and
report a resolution error at its name. Its acceptance: the guide's first example and the
examples of its sections "Values", "Databases", "Scripts" and "Row order" elaborate, and
their `decide` proofs check, except the examples of `Output.oneOf`. The model gives one
result for a query whose `LIMIT` or `OFFSET` the `ORDER BY` does not fix, so the list of
every result that SQLite may give is model work (D5). Two choices belong to its task file: whether the surface's `Database` carries
`Database.Valid` as a field, as the guide describes, and how `db!` proves it for the
database that it builds.

Amended 2026-10-22 ([ADR 0022](adr-0022-database-validity.md)): `Database.Valid` becomes the
strong notion that the guide describes, built from named facts (atoms), and today's invariant
becomes `Database.Admitted`. In S2 the surface's `Database` is the model's, `db!` also proves
`Database.Valid` for the database that it builds, and the guide's accessors read the atoms from
that proof. The `Database` that carries its validity, so that a proof needs no hypothesis, waits
for ADR 0022's theorems that the statements keep the atoms. The examples of `Output.oneOf` are
part of S2: ADR 0018's slice 6 gave the model every result that SQLite may give.

Amended again 2026-10-22 (owner decisions 3 to 5, after the measurement for the S2 task file).
The guide's run needs model work that this decision did not name, and S2 does it:

- **Outputs in the model.** The output of each statement (its rows, its number of changes and
  its result code) is computed today only in the conformance package
  (`VerifierConformance/Outputs.lean`, `PossibleOutputs.lean`, `primaryCode` in `Case.lean`).
  It moves into the model, and the conformance package uses it from there. The rows of a query
  come from `Resolved.Query.possibleOn`: one result gives `Output.rows`, in the normal form of
  the guide, and more than one gives `Output.oneOf`.
- **A run that continues after an error.** The model gets a run that resolves each statement
  against the state at the time that it runs (`resolveStatement`), runs it, and continues
  after an error, as the guide's "Scripts" section describes. A theorem states that it agrees
  with `runSqlFrom` up to and including the first error. Amended 2026-10-23: corpus-v51 holds
  the evidence for the statements after an error. Its cases are the authored cases of
  `conformance/authored_after_error.py`, recorded as version 6 records by the recorder that
  runs on after a failed statement.
- **A statement that the model does not describe, found when it runs**, gives
  `Output.unmodeled` with the model's restriction, and the run stops there: the model cannot
  say what SQLite does next, and it never approximates (D4). `sql` does not resolve at
  elaboration, so this is how its unmodeled statements show. The guide documents it.
- **No clock in S2.** The guide's `Env.default` has no clock, so a statement that reads the
  clock gives `Output.unmodeled`. `Env`, with a clock, comes with S3.

Amended a third time 2026-10-22 (owner decisions 6 and 7). This replaces the first amendment's
sentences on the surface's `Database`:

- **The `Database` carries its validity in S2.** It holds a model database and its proof of
  `Database.Valid`, and `Database.Raw` is the model database without the proof. `db!` and each
  run decide `Database.Valid` for the database that they give, and the decision is the proof
  ([ADR 0022](adr-0022-database-validity.md), D5, amended). So `db.notNull`, `db.check`,
  `db.unique` and `db.rowid_unique` need no hypothesis, as the guide says. A run whose result
  is not valid ends with `Output.unmodeled`, and its database is the one at its start. For a
  claim over every database, the check must be proved, which ADR 0022's theorems do before S4.
- **`Holds`, `Empty` and `Fails` for one database.** Their definitions come in S2, so the
  examples of the guide's "Queries as propositions" over one database are proved by `decide`.
  Their lemmas, and the claims over every database, stay in S4.

### D4. The surface never approximates

SQL that the model does not describe is an elaboration error that gives the model's
restriction and its message, at the position of the form. No slice adds a meaning that
the model does not have. A guide example that needs model work waits for it (D5).

Amended 2026-10-22 (owner decision 4): the forms differ in what they find at elaboration.
Syntax that the translation refuses is an elaboration error for every form. `sql!` and `db!`
also resolve at elaboration, so a statement that the model does not describe is an
elaboration error there, at its position. `sql` only parses at elaboration: a statement that
the model does not describe when it runs gives `Output.unmodeled` with the restriction, and
the run stops at it (D3). Neither path gives a statement a meaning that the model does not
have.

### D5. Model work that the surface waits for

The guide's claims and examples need model ADRs. They are core work on the model, not
part of this ADR; this ADR only names them and when the surface needs them:

| Model work | Needed by | Evidence |
| --- | --- | --- |
| Every result that SQLite may give for a `LIMIT` or `OFFSET` that the `ORDER BY` does not fix (`Output.oneOf`) | S2's row order examples, and S6, whose triples hold for every permitted order | guide "Row order"; open question 5 |
| Subqueries: `EXISTS`, `NOT EXISTS`, `IN (SELECT ...)` and scalar subqueries | S4: most of the guide's claims are `NOT EXISTS` queries | guide "Queries as propositions"; 332 out-of-scope cases of corpus v5 |
| `IN (...)`, `NOT IN`, `BETWEEN`, `CASE`, `||` | S4 and S6 examples | 39, 84, 27 and 105 cases; pain point 4 (`NOT IN`) |
| `DISTINCT` and `HAVING` | S4 (level 2 of the unique index) | 185 cases; pain point 3 |
| Enforced foreign keys with their actions | S6 (the rebuild that cascades) | pain point 1, the research's first-ranked failure |
| Triggers | S8 (expand/contract) | 416 cases; pain point 2 |
| Parameters, pragmas, compound `SELECT` and the table rebuild ([ADR 0019](adr-0019-guide-sql.md), D7) | S3: parameters (slice 1); S4: `pragma_table_info` and `EXCEPT` (slices 2 and 3); S6: `INSERT ... SELECT`, `RENAME` and `foreign_key_check` (slices 2, 4 and 5) | guide "Parameters", "Queries as propositions" and the lead example |
| The theorems that statements keep each fact of a valid database ([ADR 0022](adr-0022-database-validity.md)) | S4: "keys unique", and runs of the bundled database over every database, whose check the theorems replace (D3, amended 2026-10-22) | guide "Databases" |

Subqueries block S4, so their ADR should start before S3 ends.

### D6. Elaboration is outside the trusted base

The elaborated term holds the model's syntax of the SQL, and the kernel checks the
model's semantics over that term; the kernel never runs the parser (guide "What is
stored"). A wrong parser or translation therefore gives a true theorem about other SQL,
not a false theorem. The guard against it is the acceptance bar of D2, kept as a test of
the frozen corpora's texts, and the text of each claim shown next to its statement.
The surface's native code, notation and automation stay outside the kernel gate and the
judge, as ADR 0016 requires.

Amended 2026-10-21: when the Python translation is gone, the harness uses the elaborator's
translation, so the guard is the frozen corpora's predictions themselves, which the judge
compares with native SQLite. With the kernel gate removed (ADR 0021), the trusted base is
Lean's kernel over the model's definitions and the surface's terms; the surface's native code,
notation and automation stay outside it and outside the judge.

## Consequences

- **The first user-visible result is S2.** It is the guide's first example over today's
  model, and the base of every demonstration; only the examples of `Output.oneOf` wait
  for model work.
- **The launch examples depend on the model, not only on the surface.** Until the model
  has subqueries, a claim "over every database" can only use the SQL of the model's
  current subset, and the rebuild example waits for foreign keys.
- **The task after S1 replaces the Python translation.** The harness then uses the
  same translation as the elaborator (the CLI was removed by ADR 0021), so one translation exists, tested on the corpora.
- **The guide stays the target.** Each slice's task file takes its rows of the guide and
  records what it changed; the guide's open questions are decided in the slice that
  needs them.

## Alternatives considered

**Build the guide in its own order, chapter by chapter.** Rejected: the guide's order
teaches a reader, and it puts triples (S6) before counterexamples (S5), and the parser
work, which carries the risk, inside a later chapter.

**Start with programs and triples, the most distinctive part.** Rejected: they need S1
and S2 first, and the program logic depends on open questions 11 and 12, which need a
prototype of their own.

**Keep the Python translation for the CLI and the harness, and add a second one for the
elaborator.** Rejected: two translations of one grammar can disagree, and the rule for
replaced code forbids the old path.

**Approximate the SQL that the model lacks, to show the guide's examples sooner.**
Rejected: the guide's first promise is that the model never approximates, and a claim
proved over an approximation is not a claim about SQLite.

## Deferred, with their triggers

Each part of the guide that a slice does not finish is listed here, with where it is picked up.
A slice that finishes one removes it from this table, or moves it to the slice that does.

| Deferred part | Why | Picked up |
| --- | --- | --- |
| `withTransaction`, which the guide writes with a savepoint inside an open transaction | The model has no `SAVEPOINT`: a statement is `BEGIN`, `COMMIT` or `ROLLBACK` (owner decision, 2026-10-23) | When the model has `SAVEPOINT` |
| The choice of profile in the guide's `Env` | The runs of S3 use the pinned profile, and no slice gives the choice | When a second profile is in the model |
| `random()` and `randomblob()`, which the guide's `Env` lists | The model resolves them as unmodeled functions; they need model work (`changes()`, `last_insert_rowid()` and `total_changes()` have a meaning since ADR 0024, slice 1, amended 2026-10-23) | [ADR 0024](adr-0024-connection-state-and-random-values.md) (ACCEPTED): slice 2 (random values), when an example needs them |
| The theorems that replace the check of a run of the bundled database, so that a claim over every database gets the facts of the run's result | S2's run checks `Database.Valid` for each concrete run (D3, amended 2026-10-22) | ADR 0022, slices 2 to 4, before S4 |
| The name of the failed constraint in a `db!` error for a write that runs a trigger or checks foreign keys; such a write gives `constraint failed` and says that the model does not name it | The model's write with triggers or foreign-key checks does not keep why a row failed, and resolution drops the text of `RAISE`; the work is about 150 to 250 lines (owner decision, 2026-10-22) | When a user needs these messages |
| `pragma_table_info` and `pragma_foreign_key_list`, the table-valued pragma functions with which the guide states facts of a schema (narrowed 2026-10-23: the other table-valued pragma functions stay out of scope, ADR 0019 D2) | The model resolves them as a restriction | [ADR 0019](adr-0019-guide-sql.md), slice 2 (D2), before S4, whose claims over every database need schema facts |

## Not decided here

- The details of each slice after S2: its task file decides them, from the guide.
- The candidate of D2 item 2, until its measurement.
- The editor features that the guide lists (hovers, code actions, warnings for traps)
  and SQL in docstrings: each comes with the slice whose users need it.
- A benchmark of SQL tasks for agents (verification systems review, lesson 5).
- The engine interface for PostgreSQL and MariaDB (ADR 0016, deferred).

## Owner decisions

Decided on 2026-10-20:

1. **The order of D1**, with counterexamples (S5) before triples (S6).
2. **D5: the model work.** The next model ADR covers all of D5, starting with
   subqueries, so that no slice of the surface waits for the model.

Decided on 2026-10-22, for the S2 task file:

3. **Statements after an error.** S2's run continues after an error; a theorem relates it to
   `runSqlFrom` up to the first error, and the native evidence for what follows is deferred.
4. **Unmodeled statements at run time** give `Output.unmodeled`, which ends the run, and the
   guide documents it.
5. **The clock.** S2 has no clock: a statement that reads it gives `Output.unmodeled`, and
   `Env` with a clock comes with S3.
6. **The bundled database in S2** (D3, amended 2026-10-22; ADR 0022, owner decision 5): the
   surface's `Database` carries its proof of `Database.Valid`, and a run checks it.
7. **`Holds`, `Empty` and `Fails` for one database in S2**; their lemmas and the claims over
   every database stay in S4.
