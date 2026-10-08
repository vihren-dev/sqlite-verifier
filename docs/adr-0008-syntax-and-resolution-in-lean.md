# ADR 0008: Statement syntax and name resolution in Lean

Date: 2026-10-08. Status: PROPOSED.
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

Conformance cases check the rules against native SQLite. The proofs check
`resolve` against the rules.

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
  inputs change. Review condition R8 applies to each such commit.
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

- **Execution profile structure.** `resolve` takes the profile as an input. A
  structure with settings, such as foreign keys and double-quoted strings,
  replaces the current enumeration in a later decision.
- **Triggers and foreign-key actions.** Their execution semantics, as nested
  writes, need their own decision.
- **SQLite result codes.** A mapping from model errors to primary and extended
  result codes is separate work.
