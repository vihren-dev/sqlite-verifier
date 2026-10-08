# ADR 0008: Statement syntax and name resolution in Lean

Date: 2026-10-08. Status: ACCEPTED on 2026-10-08.
Audience: designers and reviewers.
Related: [ADR 0005](adr-0005-conformance-corpus-scale.md),
[ADR 0006](adr-0006-model-boundary-and-execution-levels.md),
[ADR 0007](adr-0007-parser-library.md),
[trust boundary](trust-boundary.md),
[conformance format v1](conformance-format-v1.md).

## Context

The Python frontend turns the parser's syntax tree into Lean terms. It does
three jobs in one pass, in `translate.py`, `schema_translate.py`, `sql_dml.py`
and `sql_model.py`. These files are in `migration_check/` today. PR #56 moves
them to the `belay.sqlite` package, as ADR 0006 decides, so this ADR names
them as text, not as links.

1. **Refusal.** It refuses syntax that it does not know. An error here gives
   `UNSUPPORTED`, never a wrong `VERIFIED`.
2. **Mapping.** It maps admitted syntax to model terms. An error here proves a
   theorem about other SQL than the user wrote.
3. **Resolution.** It folds names, puts columns in table order, fills omitted
   values, accepts only five type names to avoid SQLite's affinity rules, and
   computes the resulting schema in `transition`. An error here also proves a
   theorem about other SQL.

The [trust boundary](trust-boundary.md) lists this frontend as trusted code.
Jobs 2 and 3 have no formal statement. The model extension that ADR 0005
measures adds the features of its reference workload (ADR 0005, section 1.3):
queries, joins, aggregates, defaults, triggers and conflict clauses. Most of
that work is resolution: `*` expansion, alias scope, rowid aliases, and the
double-quoted string fallback that depends on the schema.

SQLite and other implementations separate these steps. They parse, then
resolve names against the schema, then execute.

## Decision

### Three layers

| Layer | Owner | Content |
| --- | --- | --- |
| `Syntax` | Lean core | Statements and expressions as written. Names are text. Omitted parts are `none`. |
| `resolve` | Lean core | Name lookup, column order, defaults, conflict mode, affinity, numeric values. |
| `Resolved` | Lean core | The statement categories of ADR 0006, with names replaced by catalog positions. |

The Python frontend maps the parser's tree to `Syntax`. Lean resolves
`Syntax` to `Resolved`. The execution semantics of ADR 0006 operate on
`Resolved` only. Resolution is SQLite behavior, so `Syntax`, `resolve` and
`Resolved` belong to the `Belay.Sqlite` core library. Their transport belongs
to `Belay.Sqlite.Codec`.

Each `match` over `Syntax` or `Resolved` has one case for each constructor, as
ADR 0006 requires for statements.

### Work that stays in Python

- **Mapping.** Each parser production maps to one `Syntax` constructor. The
  mapping does not look at the schema.
- **Refusal.** Syntax without a `Syntax` constructor gives `UNSUPPORTED`.
- **Lexical decoding.** Python removes the quotes from identifiers, string
  literals and blob literals. That is lexical work: the result depends only on
  the token.
- **Numeric literals stay text.** `Syntax` keeps the token text of each numeric
  literal. Lean converts it, because SQLite's rules are not lexical. For
  example, a decimal integer above the 64-bit range becomes a REAL value.

### Catalog

`resolve` reads and updates a catalog, which replaces today's `Schema`.

- The catalog has one namespace for tables, indexes, views and triggers, as
  SQLite's `sqlite_schema` has. A name used by one object cannot be used by
  another.
- Each entry keeps the name as written and its ASCII-folded form. Lookup uses
  the folded form. Output that SQLite spells as written uses the original.
- Each column keeps its declared type text. A Lean function computes its
  affinity with SQLite's documented rules. The same text decides rowid
  aliases: only the declared type `INTEGER` makes an `INTEGER PRIMARY KEY`
  column an alias for the rowid.

The generated starting and resulting schemas become catalogs.

### Errors from resolution

`resolve` gives one of three results for each statement:

1. **A resolved statement.**
2. **A SQLite prepare error**, for example "no such table" or "table already
   exists". SQLite runs the earlier statements and then stops at this one.
   `Resolved` therefore contains this error at its position, and the
   execution semantics treat it as a failure at that position, as today's
   `ExecutionError` does.
3. **A model restriction**: SQL that SQLite accepts but the model does not
   describe. The whole script is refused with `UNSUPPORTED`, before any proof.

Each error states which of 2 or 3 it is, as review condition R7 requires.

Resolution follows the transaction statements, as today's `transition` does.
`BEGIN` saves the catalog, `ROLLBACK` restores it, and `COMMIT` drops the
saved copy. Execution stops at the first error, so a statement after a
data-dependent failure is never prepared. `resolve` still resolves it as if
the earlier statements succeeded. If it needs a model restriction, the script
is refused. That is conservative: it never accepts unmodeled SQL.

### Diagnostics

`Syntax` terms contain no source positions, so the generated terms and the
theorem stay small. A resolution error contains the statement index and the
path of the node in the `Syntax` tree. Python keeps a table from statement and
path to the byte range in the SQL file. It turns the Lean error into a
`Rejection` with that range, so the user sees the same kind of message as
today.

### Where resolution runs

Resolution runs as compiled Lean code in the trusted gate, not in the kernel.
The kernel checks only the agent's proof.

- A trusted Lean executable runs `resolve` on `script` and writes the result
  into the generated inputs as a literal term, `resolved`.
- The gate and the bundle checker run `resolve` again on `script`. They
  compare the result with the `resolved` declaration in the compiled inputs,
  and reject a difference. A changed generated file therefore cannot change
  the target. This is the same method that the gate uses today for the
  declarations it reconstructs.
- The theorem target uses `resolved`, as it uses `script` today. Proofs operate
  on literal resolved terms.
- Python does not compute resolution.

No proof links `resolved` to `resolve script`. The link is the trusted compiled
gate. The gate already runs as compiled Lean (`migration-proof-checker` and
`migration-bundle-checker`), and the [trust boundary](trust-boundary.md)
already lists it as trusted. Resolution adds no new kind of trust: it relies on
the same Lean compiler and runtime, including the native implementations of
core functions. The trust boundary must name resolution as part of the gate.

The conversion of a computed value to a Lean term is gate code. Tests cover it,
as they cover the structural codec today: a round trip from value to term and
back, and rejection of a changed record.

### Specification of resolution

`resolve` is an algorithm. A separate declarative specification states what it
must compute, close to SQLite's documentation. Lean theorems prove that
`resolve` meets the specification for all inputs. A reviewer then reads the
rules, not the algorithm.

The specification covers at least these rules:

- **Column reference.** A reference resolves to position `i` exactly when
  column `i` has the folded name and no earlier column has it.
- **Row width.** Each resolved INSERT row has one value for each table column.
  A column named in the INSERT gets the written value. Each other column gets
  its default.
- **Unique names.** After each successful statement, no two catalog objects
  have the same folded name.
- **Prepare errors.** `resolve` gives a SQLite prepare error exactly when a
  named object is missing or a name is already used.
- **Transactions.** After `ROLLBACK`, the catalog equals the catalog at the
  matching `BEGIN`.

Each rule is a proposition with a plain-words docstring, as the repository
requires. Each theorem that uses induction or is longer than about 20 lines
has a proof sketch. A rule whose definition is already the documented rule
needs no separate proof. An example is the affinity function, which states
SQLite's documented substring rules directly.

The section "How `resolve` is tested" tells how the rules are checked against
SQLite.

### Execution profile

`resolve` takes the execution profile as an input. It reads these fields:

- **Release and source id.** They select the rules of that release, and they
  must agree with the parser dialect of ADR 0007.
- **Effective limits.** SQLite has run-time limits for each connection
  (`sqlite3_limit`). A compile-time option sets the highest value, and the
  connection can lower it. The value that applies is the current value of the
  connection. The profile records these limits:

  | Limit | Value recorded for 3.51.0 | Checked by |
  | --- | --- | --- |
  | Columns in a table, an index or a result list | 2,000 | `resolve` |
  | Expression depth | 1,000 | `resolve` |
  | Terms in a compound `SELECT` | 500 | `resolve` |
  | Function arguments | 1,000 | `resolve` |
  | Highest parameter number | 32,766 | `resolve` |
  | Length of a text or blob value | 1,000,000,000 | execution semantics |
  | Trigger depth | 1,000 | execution semantics |

- **Double-quoted strings.** The `DQS_DML` and `DQS_DDL` settings decide if a
  double-quoted name that matches no column becomes a string literal.

No limit is a constant in Lean or Python. Today, 2,000 columns is a constant in
`SqliteVerifier/Model.lean` and in four Python files, and the native recorder
forces the column limit of each connection to 2,000. All of these are removed.
Model validity, such as the column count of a valid table, uses the limit of
the profile.

SQLite checks the expression depth in its parser actions. The parser library of
ADR 0007 replaces those actions, so `resolve` enforces this limit.

**Measurement.** The native recorder reads each limit of the connection with
`sqlite3_limit(db, id, -1)` and records it in the profile, next to the
settings that it records today. A profile for an application is measured on a
connection that the application configures, as ADR 0005 requires. If the
application lowers a limit, its profile shows the lower value.

**Frozen records.** Profiles in frozen records have no limits field. Their
recorder kept every limit at the compile-time value, and set the column limit
to 2,000, which is also the default. A reader therefore takes the limits of an
old profile from the `SQLITE_MAX_*` values in its recorded compile options. No
frozen record changes.

**In Lean.** `ExecutionProfile` becomes a structure with the release, the
source id, the limits and the double-quoted-string settings. It replaces the
enumeration with one constructor for each release. The generated inputs
contain the profile as a literal. For `verify`, a release version on the
command line selects SQLite's documented defaults for that release, until a
user can give a measured profile.

The other recorded settings, such as foreign keys, recursive triggers, the
transaction mode and the clock, belong to the execution semantics. Their place
in the structure is part of a later decision.

### How `resolve` is tested

`resolve` is checked in two ways. Each way covers a different question.

| Question | Method |
| --- | --- |
| Do the rules say what SQLite documents and does? | Review of the specification against the documentation, and the conformance suite |
| Does `resolve` follow the rules, for all inputs? | Lean proofs |

**Specification with documentation references.**

- Each rule of the specification has a docstring with the documentation page of
  the pinned release that it implements. Where the documentation has a
  requirement identifier, such as `R-12345-67890`, the docstring names it. The
  identifiers are in the requirement inventory of the corpus.
- Where the documentation does not state the behavior, the docstring names the
  function in the pinned SQLite source that decides it. Each such rule needs at
  least one conformance case, because no document can confirm it.
- A reviewer checks each rule against its reference. This review is the only
  check that the rule says what SQLite documents.

**Conformance suite.** The suite runs each case through the mapping, `resolve`
and the execution semantics, and compares the observations with native SQLite.
SQLite does not show its resolution result, so the suite compares its effects:

- **Prepare errors.** The result code, the error position and the error kind.
  Almost all prepare errors have the same result code, `SQLITE_ERROR`, so the
  kind is necessary. Each error kind in Lean names the SQLite message format
  that it corresponds to, such as `no such table: %s`, and the comparison
  matches the recorded message against that format.
- **Error phase.** The case format records if an error came from
  `sqlite3_prepare_v2` or from `sqlite3_step`. Today the recorder does not
  record this. A prepare error must agree with `resolve`. A step error must
  agree with the execution semantics. For example, adding a `NOT NULL` column
  without a default fails only when the table has rows, so SQLite reports it
  when the statement runs.
- **Catalog.** After each statement, the catalog of `resolve` is compared with
  `sqlite_schema`, `PRAGMA table_xinfo` and the index lists: object kinds,
  names as written, declared type text, defaults and keys.
- **Result columns.** The result column names, and the declared type of each
  result column from `sqlite3_column_decltype`. In builds with
  `SQLITE_ENABLE_COLUMN_METADATA`, also the origin table and column.
- **Stored rows.** Exact storage classes and values. These show column order,
  defaults, affinity and numeric literal conversion.

Errors, the catalog and the result columns check `resolve` almost alone.
Stored rows also depend on the execution semantics.

**Coverage rule.** An authored shard contains, for each condition of each
rule:

- at least one case where the condition applies;
- a neighbor case where it just does not apply, for example a name that
  differs only outside ASCII, or one column below a limit;
- cases where two errors apply at once, to record which error SQLite reports.

Each case names the requirement identifiers that it covers, so the requirement
matrix of the progress report shows the coverage of each rule. Cases from the
upstream Tcl tests that cover the same rules are further evidence.

**Limits.** Limit cases are recorded under profiles with lowered limits, for
example 5 columns or text of 100 bytes. A model that uses a constant instead of
the profile value then fails. The suite needs no table with 2,000 columns and
no value of one gigabyte. One case for each limit is also recorded at the
default value, to show that a lowered limit and the compile-time limit give the
same result.

**Mutants.** Changed copies of `resolve` check that the suite tests each rule.
Each of these mutants must make at least one case disagree:

- fold non-ASCII letters too;
- change the order of the affinity rules;
- make `INTEGER PRIMARY KEY DESC` an alias for the rowid;
- keep the catalog after `ROLLBACK`;
- permit a table and an index with the same name;
- use 2,000 columns instead of the profile limit;
- remove one prepare-error condition at a time.

A mutant that no case kills shows a missing case.

**Current coverage.** The current corpora have 4,466 distinct cases. 380 of
them end in an error. Most of those errors are in features after the first
scope, such as `ALTER TABLE ... RENAME`, JSON functions and aggregates. For the
first scope, the compared cases contain no case for these conditions:

- `CREATE TABLE` for a table that exists;
- a duplicate column in `ADD COLUMN`;
- a table with the name of an index;
- more columns than the limit;
- an ambiguous column name in a query;
- `COMMIT` or `ROLLBACK` with no active transaction;
- two errors in one statement.

Errors in the setup of upstream cases are not counted. The model does not
compare setup. The authored shard closes these gaps.

### Scope of the first implementation

- Today's seven statements: CREATE TABLE, ADD COLUMN, BEGIN, COMMIT, ROLLBACK,
  INSERT and UPDATE.
- The expression and query syntax of the reference workload in ADR 0005,
  section 1.3.

Python refuses all other syntax.

### Transport

The conformance runner input and the structural record of the bundle checker
carry `Syntax` instead of resolved statements. Each gets a new format version.
Frozen corpus records are not affected: they contain SQL text and native
observations, and replay translates the SQL again each time.

## Evidence

A prototype in Lean 4.34.1, with Lean core only, had `Syntax`, `resolve` and
`Resolved` for CREATE TABLE, ADD COLUMN, CREATE INDEX, INSERT with a column
list, UPDATE and SELECT. It included ASCII folding, the affinity rules,
defaults and column positions. The test scripts had 6 tables, 9 added columns,
9 indexes and 46 other statements for each scale unit.

| How `resolve` ran | 70 statements | 1,120 statements |
| --- | --- | --- |
| Kernel, `resolve` for the whole script | 116 s | not run |
| Kernel, step-wise check against literal catalogs | 2.4 s | 68 s |
| Lean interpreter (`lean --run`) | 1.4 ms | 30 ms |

Kernel times exclude about 1.4 s to start Lean. Natively compiled code was not
measured; it is usually faster than the interpreter.

The kernel checks proofs by rewriting terms. It does not compile code, it
keeps few intermediate results, and only natural-number arithmetic has a fast
path. The direct evaluation was slow because each statement passes on a
catalog that is not yet computed, and each later lookup computes the chain
again. The step-wise check removed that cost, with a soundness theorem that
links it to `resolve`. It was still about 1,700 times slower than the
interpreter. These measurements are the reason that resolution runs in the
compiled gate.

The prototype also proved one specification rule for all inputs: the column
reference rule, as a theorem in both directions with one helper lemma, in
about 50 lines. It depends only on `propext`, `Classical.choice` and
`Quot.sound`.

## Consequences

- **Less trusted Python.** The trusted mapping is one constructor for each
  production. Resolution has Lean definitions, a declarative specification and
  proofs that connect the two.
- **Conformance tests resolution.** Corpus cases go through `resolve` and then
  the execution semantics. A difference from native SQLite can come from
  either, and both are Lean code.
- **Owner review.** The verification target, the gates and the generated
  inputs change. Model validity depends on the profile limits. Review
  condition R8 applies to each such commit.
- **Recorder and formats.** The recorder no longer forces the column limit. The
  profile format gets a limits field, and the case format gets the error phase.
  Both get new versions. Frozen records stay readable.
- **Time.** Resolution adds milliseconds to each `verify`. The kernel time is
  spent on the agent's proof.
- **Trust boundary.** It names resolution as part of the compiled gate. The
  link from `script` to `resolved` relies on that gate, not on a proof.
- **Proof work.** The specification and its proofs are new library work. The
  prototype rule suggests a few hundred lines for the first scope. This is an
  estimate, not a measurement.
- **ADR 0006.** Its statement categories and `Admitted` predicates become the
  `Resolved` layer. `Syntax` and `resolve` are added above them. Its package
  and level decisions are unchanged.
- **More places to change.** A new construct needs a `Syntax` constructor, a
  `resolve` case and a semantics case.

## Cleanup after implementation

The new layers replace resolution in Python, the current model statements and
the column constant. The repository rule for replaced code applies: no
fallback, alias or legacy path remains. File names in the frontend are the
names after PR #56, in `belay/sqlite/`.

**Python frontend.** The frontend keeps the mapping to `Syntax`, the refusal of
unknown syntax, lexical decoding and the table of source positions. It loses
all work that depends on the schema or on SQLite's value rules:

- In `translate.py`, `schema_syntax.py` and `schema_translate.py`: case
  folding, the five accepted type names and the affinity mapping, the checks
  for duplicate, reserved and too many columns, key and index resolution, and
  `validate_migration`.
- In `sql_dml.py`: the column positions of INSERT and UPDATE, and the check of
  the value count.
- `sql_admission.py`: the checks of value conversion and of the key domain.
  They become model restrictions in `resolve`.
- In `sql_values.py`: the conversion of numeric literals. Lexical decoding of
  strings and blobs stays.
- In `sql_model.py`: the Python model types `Column`, `Index`, `Table` and
  `Statement`, their Lean emitters, and `transition`. The frontend emits
  `Syntax` terms instead.
- In `structural.py`: the encoding of the current statements and schemas. It
  encodes `Syntax` in the new format version.
- The constant 2,000 in each of these files.

**Lean model.**

- `Schema`, `TableSchema` and `TableProperties` with nested indexes, and their
  lookup functions. The catalog replaces them.
- `DeclaredType` and `declaredTypeMatches`. The declared type text and the
  affinity function replace them.
- `maximumColumns` in `Model.lean`. Validity uses the profile limit.
- The enumeration `ExecutionProfile`. The profile structure replaces it.
- The current `Statement` type with names. `Resolved` replaces it.
- The errors `tableExists`, `missingTable`, `columnExists` and
  `tooManyColumns` as execution errors. They become prepare errors of
  `resolve`. The execution semantics keep the failure position.
- The decoders of the current statements and schemas in the structural codec.

**Generated inputs and gate.** `startSchema`, `nextSchema` as a Python
computation, and `script` as a list of named statements. The generated inputs
contain the start catalog, `script` as `Syntax`, `resolved` and the profile.

**Recorder and conformance harness.**

- The forced column limit of 2,000 and its readback check in
  `native_connection.py`.
- The comparison of Python statements in `native_replay.model_case`, which
  aligns native statements with Python translation results.
- The cross-check of Python schema translation against native metadata in
  `native_metadata.py`. The comparison of the catalog after each statement
  replaces it.

**Tests.**

- Tests of resolution decisions in Python: the affinity, default, key, limit
  and duplicate cases in `test_translation.py`, `test_schema_translation.py`,
  `test_sql_writes.py` and `schema_generation_test.py`. Each case moves to the
  specification proofs, to Lean examples of `resolve`, or to the conformance
  suite. Cases that test only the mapping to `Syntax` stay in Python.
- The checks in `generated_inputs_test.py` that compare declarations with the
  Python emitter.
- Cases that need a table with 2,000 columns, such as the column boundary in
  `conformance_generation_test.py`. Cases under a profile with a lowered limit
  replace them.

**Documentation.** The documents that describe the replaced parts change in the
same work: [conformance format v1](conformance-format-v1.md) for the statement
encoding, [execution profile](execution-profile.md),
[data path](data-path.md), [kernel gate](kernel-gate.md),
[source staging](source-staging.md), [trust boundary](trust-boundary.md),
[conformance model](conformance-model.md) and
[conformance generation](conformance-generation.md).

**Kept.** Frozen corpus records and their readers are historical evidence and
stay. They contain SQL text, not statements, so no reader of the replaced
statement encoding is necessary for them. Reports, plans and accepted ADRs
stay as records.

**Checks that the cleanup is complete.**

- No Python module in the frontend imports a catalog or schema type, or
  contains an affinity rule, a case-folding function or the constant 2,000.
- No Lean or Python file outside reports, plans and ADRs uses `DeclaredType`,
  `maximumColumns`, `.sqlite351` or `.sqlite346`.
- Each removed Python test case of a resolution decision has a named
  replacement: a proof, a Lean example or a conformance case.

## Alternatives considered

**Keep resolution in Python.** Rejected. The resolution needed for queries is
large and depends on the schema. It would be trusted code with no formal
statement.

**Evaluate `resolve` directly in the kernel.** Rejected. It took 116 s for
70 statements.

**A kernel check of each resolution with a step-wise certificate.** Rejected.
It took 2.4 s for 70 statements, about 1,700 times the interpreter time. It
would only detect a difference between the compiled code and the definition
of `resolve`. The project trusts the Lean compiler, as the compiled gate
already requires.

**The same kernel check as a continuous-integration audit.** Rejected for the
same reason: it adds no protection that the trusted compiler does not already
give.

**Compute the resolved terms in Python.** Rejected. Python would need a second
implementation of resolution.

**Source positions in `Syntax`.** Rejected. They make the terms and the
theorem larger, and the proof does not use them.

## Not decided here

- **Other profile settings.** This ADR decides the profile fields that
  `resolve` reads. The place of foreign keys, recursive triggers, the
  transaction mode and the clock in the structure is a later decision, with
  the execution semantics that use them.
- **Measured profiles for `verify`.** How a user gives a measured profile to
  `verify`, instead of a release version, is a later decision.
- **Triggers and foreign-key actions.** Their execution semantics, as nested
  writes, need their own decision.
- **SQLite result codes.** A mapping from model errors to primary and extended
  result codes is separate work.
