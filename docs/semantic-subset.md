# Supported schema-extension subset

The production translator consumes the complete pinned SQLite CST. It admits
ordinary `CREATE TABLE` and `ALTER TABLE … ADD [COLUMN]` with explicit unquoted
`INTEGER`, `REAL`, `TEXT`, `BLOB`, or `NUMERIC` types (case insensitive).
New columns are nullable, have implicit NULL defaults, and have no constraints.
Migration CREATE remains limited to unconstrained tables; it rejects when the
baseline contains keys, indexes, NOT NULL constraints or timestamp defaults.
Identifiers use SQLite quoting and ASCII-only case normalization; non-ASCII
case distinctions are preserved. Each table has at most 2,000 distinct columns.

The declarative starting schema additionally retains unquoted BIGINT, TIMESTAMP,
BOOLEAN and omitted type declarations; NOT NULL; a single inline non-rowid-alias
PRIMARY KEY; unnamed table UNIQUE constraints; CURRENT_TIMESTAMP defaults; and
named plain-column indexes, including UNIQUE indexes. Default conflict behavior
and column ordering are retained. Type spelling is normalized to supported
declarations and affinity, without claiming textual SQL identity. In particular,
nullable TEXT primary keys remain nullable, separate from physical rowid.

INTEGER PRIMARY KEY aliases, other defaults/constraints, named constraints,
collations, expression/partial indexes, explicit index sort modifiers, type
parameters, generated columns, rowid-shadowing names, table options, conditional
creation and temporary/qualified objects remain unsupported. Views, triggers,
virtual tables and other dependencies reject; none are silently dropped. The
only admitted reserved names are the exact native sqlite_stat1 and sqlite_stat4
table definitions, retained as persisted baseline objects. Migration SQL cannot
create or alter them. Quoted type names remain unsupported.

The entire supplied starting schema must fall within this subset. An empty
starting schema is allowed. The CLI must
require at least one migration statement. Every command retains its original
half-open UTF-8 byte span; semicolons in names and trigger bodies cannot split
commands. Unsupported syntax wrappers, including EXPLAIN, are rejected.

Translation computes sequential payload schema effects. A duplicate table, missing
table, duplicate added column, or exceeded column limit stops the script and
retains the successful prefix under autocommit. Column-limit failure precedes duplicate-column
failure, matching the pinned native engine. If failure is inevitable, the
generated next schema is that prefix; the formal contract must still establish
the approved applicability and failure guarantees. Predicting an execution
error alone never establishes `VIOLATED`. No profile implicitly wraps the SQL
in a transaction or changes bookkeeping. See [execution profiles](execution-profile.md)
and [profile input](profile-inputs.md).

`SqlInputs.lean` contains only structural schema/statement constructors and inert
quoted names. The driver seals it separately from candidate definitions. A
translation result is not proof acceptance or evidence of native execution.

## Explicit transactions and literal data operations

Transactions and data changes are supplied as SQL, not implied by a profile.
The additional subset admits BEGIN, COMMIT and ROLLBACK, single-row literal
INSERT with every column supplied in schema order, and one literal UPDATE
assignment selected by equality to an integer on a single-column unique key.
These operations apply to ordinary supported tables irrespective of their names.

Literal DML has checked data-domain obligations. Assigned values must retain
their storage classes under affinity; comparisons and unique keys use bounded
integers or NULL in non-TEXT columns. Existing constraints must hold, and new
NOT NULL/uniqueness violations are modeled statement failures. Unsupported
coercions or comparison classes are not invented SQLite error outcomes. INSERT
uses ordinary automatic rowid allocation; the random-search branch at maximum
rowid is outside the admitted domain. Defaults are not implicitly evaluated by
the full-column literal INSERT subset.

An error inside a transaction does not imply rollback. The model distinguishes
the connection-visible state from its committed snapshot when a transaction
remains open. A final uncommitted transaction cannot be reported as a committed
successful migration. Resource, concurrency and crash failures remain outside
the fixed execution assumptions.

The [Atuin example](../examples/atuin/README.md) uses these generic operations.
Its literal timestamp and elapsed duration represent one documented SQL instance;
the verifier does not supply a clock, interpret a framework catalog, or execute
the application.
