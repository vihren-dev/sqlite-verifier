# Initial schema-extension subset

The production translator consumes the complete pinned SQLite CST. It admits
ordinary `CREATE TABLE` and `ALTER TABLE … ADD [COLUMN]` with explicit unquoted
`INTEGER`, `REAL`, `TEXT`, `BLOB`, or `NUMERIC` types (case insensitive).
Columns are nullable, have implicit NULL defaults, and have no constraints.
The schema model records canonical affinities, not original type spelling.
Identifiers use SQLite quoting and ASCII-only case normalization; non-ASCII
case distinctions are preserved. Each table has at most 2,000 distinct columns.

Omitted types, type parameters, constraints, explicit defaults, generated columns,
rowid-shadowing names, reserved `sqlite_` names, table options, conditional
creation, temporary/qualified tables, and other SQL commands are unsupported.
This is a deliberate semantic subset of the full grammar. Quoted type names
also remain unsupported even when SQLite would give them a supported affinity.

The entire supplied starting `.schema` must describe supported ordinary tables.
Views, indexes, triggers, virtual tables, and other dependencies are rejected;
none are silently dropped. An empty starting schema is allowed. The CLI must
require at least one migration statement. Every command retains its original
half-open UTF-8 byte span; semicolons in names and trigger bodies cannot split
commands. Unsupported syntax wrappers, including EXPLAIN, are rejected.

Translation computes sequential schema effects. A duplicate table, missing
table, duplicate added column, or exceeded column limit stops the script and
retains the successful prefix. Column-limit failure precedes duplicate-column
failure, matching the pinned native engine. If failure is inevitable, the
generated next schema is that prefix; the formal contract must still establish
the approved applicability and failure guarantees. Predicting an execution
error alone never establishes `VIOLATED`.

`SqlInputs.lean` contains only structural schema/statement constructors and inert
quoted names. The driver seals it separately from candidate definitions. A
translation result is not proof acceptance or evidence of native execution.
