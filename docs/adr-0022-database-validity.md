# ADR 0022: The facts of a valid database, and the statements that keep them

Date: 2026-10-22. Status: ACCEPTED on 2026-10-22 (owner decision in the design discussion of
ADR 0017's slice S2).
Implementation: slice by slice (D4), each with its own task file, as local commits.
Audience: designers and reviewers.
Related: [ADR 0012](adr-0012-query-semantics.md) (decision 5, the admitted databases),
[ADR 0016](adr-0016-model-and-surface.md) (the layer rules),
[ADR 0017](adr-0017-user-surface.md) (the user surface, D3 and D5),
[ADR 0019](adr-0019-guide-sql.md) (D2, `PRAGMA integrity_check`).

## Overview

A user expects that a database satisfies the constraints of its schema: NOT NULL, CHECK, the
keys and the types of a `STRICT` table. The model's invariant `Database.Valid` does not say
this, on purpose: SQLite can reach databases whose constraints fail, and ADR 0012 admits every
database that SQLite can reach.

This ADR keeps both notions and builds them from small named facts, the atoms. A user can use
each atom alone, or a bundle of them: `Database.Valid`, the strong notion that users expect, and
`Database.Admitted`, today's weaker invariant under a new name. For each atom, a theorem says
which statements keep it. Each theorem is its own work, which the slices of D4 deliver in the
order in which the user surface needs them.

## Context

Measured on this tree on 2026-10-22:

- **Today's invariant.** `Database.Valid` (`Model/Database.lean:148`) requires a supported
  catalog (`Catalog.Valid`), one row list for each catalog object, no rows at an index's
  position, and for each table: distinct rowids, each in the signed 64-bit range, one cell for
  each column, each cell in its stored form, and the rowid in the cell of a rowid alias. Its
  docstring says: "Native representability and constraint truth are separate claims."
- **Why it is weak.** ADR 0012, decision 5: an invariant may join it "only if it holds for every
  database that SQLite can reach". Constraints can fail in such databases: after
  `PRAGMA ignore_check_constraints`, after a write to the schema with `writable_schema`, in a file
  that another program wrote, or after writes with foreign keys off.
- **The model checks the constraints already.** `LiteralData.constraints`
  (`Model/LiteralData.lean:90`) checks NOT NULL, the types of a `STRICT` table, CHECK and the
  unique keys of the catalog (`Catalog.uniqueKeys`). INSERT, UPDATE and upsert store a table only
  after it passes this check. Plain INSERT and UPDATE check their whole result once
  (`checkedWrite`, `Model/StatementRun.lean:19`). Upsert, and the writes that check foreign keys
  or run triggers, check the table after each row (`checkedRow`, `Model/Upsert.lean:57`), and a
  FAIL failure keeps the rows that the write stored before it. The model describes these writes
  only when the table passes the check before (`tableReady`). DELETE uses neither check: it
  removes the selected rows from any table (`runStatement`, `Model/StatementStep.lean`), also
  from a table whose constraints fail.
- **No statement has a preservation theorem.** The model has lemmas for single operations
  (`Conforms.setRows`, `Conforms.addColumn`, `Conforms.createTable`,
  `Catalog.emptyDatabase_conforms`), not for a statement. ADR 0012 says that "a preservation
  theorem shows that the model's statements keep every invariant" (line 444); it does not exist.
- **Decidability.** `Catalog.Valid` is decidable. `Database.Valid` is not: it quantifies over
  every position and every value.
- **The user guide** ("Databases") says that each `Database` satisfies its constraints, and that
  a proof reads them with `db.notNull`, `db.check`, `db.unique` and `db.rowid_unique`.
- **ADR 0019, D2** relates the `ok` row of `PRAGMA integrity_check` to `LiteralData.constraints`,
  because `Database.Valid` does not include them.

## Decision

### D1. The atoms

Each atom is one fact about one table of a database, at its position in the catalog, or about the
whole database. Its database form says the fact for every table.

| Atom | It says | Bundle |
| --- | --- | --- |
| catalog supported | the catalog satisfies `Catalog.Valid` (database) | Admitted |
| rows shaped | one row list for each catalog object, and no rows at a position without a table (database) | Admitted |
| rowids distinct | no two rows of the table have the same rowid | Admitted |
| rowids in range | each rowid is in the signed 64-bit range | Admitted |
| rows wide | each row has one cell for each column | Admitted |
| rows stored | each cell is in the stored form of its column's affinity | Admitted |
| rows aliased | the cell of a rowid alias is the row's rowid | Admitted |
| not null | no NOT NULL column holds NULL | Valid |
| checks hold | no CHECK constraint is false for a row | Valid |
| types fit | each cell of a `STRICT` table fits its column's type | Valid |
| keys unique | no two rows conflict on a unique key of the catalog: PRIMARY KEY, UNIQUE, unique indexes with their filters, terms and collations | Valid |
| foreign keys hold | each child row matches a parent row or has a NULL in its key | neither |

Each atom has two forms: a proposition that a proof reads easily, and a check that computes,
with a lemma that the two are equivalent. The atom is decidable through its check, so `decide`
proves it for a concrete database. The checks of the constraint atoms are the functions that
the writes use (`LiteralData`), so "valid" means what the model's writes enforce. The atoms are
public in the model and named in the surface. The task file of slice 1 gives their names.

### D2. Two bundles

- **`Database.Admitted`** is today's `Database.Valid` under a new name: a structure with one
  field for each Admitted atom. It describes every database that SQLite can reach, as ADR 0012
  requires. `Conforms` becomes a fixed catalog and `Database.Admitted`.
- **`Database.Valid`** is a structure with a field for `Database.Admitted` and one field for each
  Valid atom. It describes the databases that users expect: the databases that SQLite reaches
  through statements, with no pragma or file that bypasses the constraints.

A field is an accessor: from `valid : db.Valid profile`, `valid.notNull` is the atom. Both
bundles are decidable. A claim for every database states `Database.Valid` as its hypothesis; a
claim that must hold also for databases with broken constraints states `Database.Admitted` and
the atoms that it needs.

### D3. A theorem for each atom

For each atom, a theorem says that a statement that the model describes keeps the atom. A
theorem can require a condition on the connection, for example that foreign keys are on. A
statement that can break an atom, such as `PRAGMA ignore_check_constraints` if the model
describes it, has no theorem for that atom; the theorems of the other atoms still apply to it.
A frame lemma says that a statement keeps an atom of a table when it changes nothing that the atom
reads: the table's rows and catalog entry, and also its indexes for "keys unique" and the parent
tables for "foreign keys hold". A DELETE of a parent row with foreign keys off changes no row of
the child table, but breaks the child's "foreign keys hold".

The theorems are about the model's statement step (`runStatement`) and its runs (`runSql`). A
failed statement keeps the database that the model gives for it. The model refuses
`DEFERRABLE INITIALLY DEFERRED` keys today, so the foreign key atom holds after each statement
while foreign keys are on; deferred keys change the theorem when the model describes them.

A proof that fails is a finding: an error of the model, or a path through which SQLite breaks
the fact. It is reported to the owner, and no proof assumes it away.

### D4. Slices

| Slice | Content | Needed by |
| --- | --- | --- |
| 1 | the atoms, their checks, the two bundles, the rename | ADR 0017 S2: the checked run of the bundled database (D5, amended) |
| 2 | the theorem of "keys unique" | ADR 0017 S4: a lookup by key gives at most one row |
| 3 | the theorems of the other Valid atoms | ADR 0017 S4: a run of the bundled database over every database (D5, amended) |
| 4 | the theorems of the Admitted atoms | ADR 0017 S4, as slice 3 |
| 5 | the theorem of "foreign keys hold" | ADR 0017 S6: the rebuild that cascades |

Record of slice 2 (2026-10-23, `plans/20261023-keys-unique.task.md`): the statement theorem
`runStatement_keysUnique` holds for every statement form, foreign keys and triggers included,
with a condition only for ADD COLUMN (`Database.AddColumnCondition`) and DROP
(`Catalog.DropCondition`). The run theorems of `runSqlFrom`, `runSql` and `runScriptFrom` assume
that each CREATE INDEX, ADD COLUMN and DROP that the run reaches meets its condition. This is an
owner decision of 2026-10-23 after a finding: a resolved CREATE INDEX of an index that
`CatalogIndex.supported` refuses runs, and a later ADD COLUMN then breaks the atom. Slice 4 also
proves the resolver facts that give these conditions, and removes the hypothesis from the
theorem of `runScriptFrom`; the theorem of `runSqlFrom` keeps it.

Record of slice 3 (2026-10-23, `plans/20261023-valid-atoms-theorems.task.md`): the statement
theorems `runStatement_notNull`, `runStatement_typesFit` and `runStatement_checksHold` hold for
every statement form, foreign keys and triggers included, and they assume only their own atom.
The only condition is on ADD COLUMN: the rows of the table are as wide as the table
(`Database.RowsWideAt`), the stored default fits the strict type (`Database.StrictDefaultFitsAt`,
"types fit"), and each CHECK reads only columns below the width (`Database.ChecksReadBelowAt`,
"checks hold"). A counterexample in `RowLocalExamples` shows that each condition is necessary. The
run theorems of `runSqlFrom`, `runSql` and `runScriptFrom` exist for each atom, and for the four
constraint atoms together (`Database.ConstraintAtoms`: `runSql_constraintAtoms`,
`runSqlFrom_constraintAtoms`, `runScriptFrom_constraintAtoms`), where the conditions are the
conditions of slice 2 and of the three atoms. Slice 4 proves the width condition and the type
condition as facts of resolved scripts. The CHECK condition is also a fact of the start database,
which no atom states today (status file, decision 3), so the hypothesis of `runScriptFrom` goes only
with such an atom; the theorems of `runSqlFrom` keep the hypotheses. By owner decision 1a, the row engine of slice 2 and its run theorems take the atom as a
parameter (`RowEngineFacts`, `RunHolds`), and slice 2 is the instance for "keys unique". No proof
failed. Amended 2026-10-23: the pragma forms of ADR 0019, slice 2 are now in this line of changes;
the statement theorem of `RowLocalStatement` has a case for each constructor of `Resolved.Statement`
and covers them.

Record of slice 4, part 1 (2026-10-24, `plans/20261023-admitted-atoms-theorems.task.md`):
`Catalog.Valid` now states three more facts about a table. Each CHECK reads only columns of its
table. A rowid alias is a column that is not generated and has INTEGER affinity, is the whole primary
key, and is in a table that is not `WITHOUT ROWID`. A key may name a column twice, as SQLite allows
(`PRIMARY KEY(a, a)`); the model does not restrict it, and the facts of slice 2 hold for such keys. So
the CHECK condition of slice 3 is a fact of every admitted database, and it is no longer a gap.
The resolver keeps `Catalog.Valid` for CREATE TABLE, CREATE INDEX, CREATE TRIGGER, ADD COLUMN and
DROP (`resolveStatement_valid`, `resolve_valid`, with the catalog that BEGIN saves for ROLLBACK). The
resolved DROP meets `Catalog.DropClosed`, from which `Catalog.DropCondition` follows. An admitted
database meets `Database.AddColumnCondition`, `Database.RowsWideAt` and `Database.ChecksReadBelowAt`,
and the resolved ADD COLUMN meets `strictDefaultFits`. A CREATE INDEX with no key terms is a prepare
error that SQL text cannot reach. The statement theorems and the run theorems are parts 2 and 3.

Record of slice 4 (2026-10-24, `plans/20261023-admitted-atoms-theorems.task.md`): each atom of
`Database.Admitted` has a statement theorem (`runStatement_rowidsDistinct`, `runStatement_rowsShaped`,
`runStatement_catalogSupported`, `runStatement_rowidsInRange`, `runStatement_rowsWide`,
`runStatement_rowsStored`, `runStatement_rowsAliased`), and a run theorem for `runSqlFrom`, `runSql` and
`runScriptFrom` (`runSqlFrom_rowsShaped` and so on, and `runSqlFrom_admitted` for the bundle). By owner
decision M, the row engine tests each row that it writes (`LiteralData.rowAdmitted`), so the statement
theorems of "rowids in range", "rows wide", "rows stored" and "rows aliased" assume that the run is ready
(the support check of the model passes); the run theorems of `runSqlFrom` and `runSql` assume
`supportedSqlFrom`, and `runScriptFrom` gets it from the run, which ends at a statement that fails it.
"Catalog supported" and "rows aliased" also assume that the catalog after each statement is valid
(`Resolved.Statement.AppliedValid`). A theorem lists the atoms that it needs: "rows stored" lists "rows wide",
and "rows aliased" lists "catalog supported". The theorems of `runScriptFrom` have no hypothesis on the
statements of the script. The resolver facts of part 1 give the conditions: `Resolved.Statement.SchemaLink`
(ADD COLUMN: the default fits the strict type; DROP: `Catalog.DropClosed`) is a fact of every successful
resolution against a valid catalog (`resolveStatement_schemaLink`, with `state.catalog.Valid limits`), stated positively because CREATE TRIGGER IF NOT EXISTS of an
existing trigger resolves to a DROP of no object. The `runScriptFrom` theorems of the constraint atoms assume
`Database.AdmittedWith profile atom` (admitted, with the atom), a context in execution mode, and the limits
of the context equal to those of the profile; `Database.ConstraintAtoms` together give the corollary
`runScriptFrom_valid`: a run of `runScriptFrom` from a connection with a valid database and snapshot ends in
one, with `Database.valid_empty` for a new connection. The surface form is `Sql.runFrom_valid`, by induction
over the program, and `Sql.runFrom_database_valid`. The conditions stay in the theorems of `runSqlFrom` and
`runSql`, and `AdmittedRunsConditionExamples` shows a run that breaks the atom for each: a rowid past the
largest, and a DROP of a table that leaves its index. The check `Run.checked` is not removed yet; ADR 0017,
S4 removes it with these theorems. No proof failed. The predictions, the claims and the judge lock do not
change.

For the constraint atoms, INSERT, UPDATE and upsert are the easier case: each table that they
store passed the checks, after the whole write or after each row, and a proof follows those
steps, also for the rows that a FAIL failure keeps. DELETE removes rows, and each constraint
atom is a fact of each row or of each pair of rows, which fewer rows keep. Schema statements,
trigger programs and foreign key actions are the larger work. No slice
changes what a statement does, so the predictions, the claims and the judge lock do not change.

### D5. The bundled database stays open

The guide's `Database` carries its validity, so that a proof gets the facts "without extra
hypotheses". That needs `db.run` to keep `Database.Valid`, which slices 2 to 4 prove. Until then,
the surface's `Database` is the model's, and `db!` gives a proof of `Database.Valid` beside it.

A decision for later, with the bundled type: a script with a statement that has no theorem for
an atom cannot give a bundled result. Either elaboration refuses such a statement in a bundled
run, or the run gives a database with the weaker bundle.

Amended 2026-10-22 (owner decision 5): the bundled database comes in S2, with a run that checks
instead of proves. The surface's `Database` holds a model database and its proof of
`Database.Valid`; a plain model database without the proof has its own name, `Database.Raw`,
for the claims that must cover databases with broken constraints (`Database.Admitted`). A run
computes the model's result as before, and then decides `Database.Valid` for the database at
its end (slice 1). When it holds, that decision is the proof of the bundled result. When it
does not, the run's outputs end with `Output.unmodeled`, whose reason says that the result is
not a valid database, and the run's database is the one at its start; the model's result stays
readable as a `Database.Raw`. The run never presents a database that is not valid as one that
is.

- **For one concrete database** this gives the guide's experience: `db.notNull` needs no
  hypothesis, for the database of `db!` and for the database after a run, and `decide` checks
  the run.
- **For a claim over every database** (ADR 0017, S4 and later), a proof must show that the
  check holds, which is the theorems of D3. Slices 2 to 4 therefore come before S4; with them,
  the check is proved to hold, and the run can give the proof without the check.
- **The else branch is a finding** while the model describes no statement that bypasses a
  constraint: a run that reaches it shows an error of the model, which D3 reports to the
  owner. When the model describes such a statement, the else branch is how a run treats it,
  which decides the question of the previous paragraph for runs of the bundled database.

## Consequences

- **The guide states both notions.** Its "Databases" section names the atoms, says which
  databases a claim over `Database` covers, and points to `Database.Admitted` for the others.
- **ADR 0012's preservation sentence** is corrected by an amendment that points here.
- **ADR 0019, D2** gets a simpler law: the `ok` row of `integrity_check` is the Valid constraint
  atoms, and of `quick_check` the same without "keys unique", under `Database.Admitted`
  (done with ADR 0019's acceptance, 2026-10-22).
- **The work is a matrix** of atoms and statement forms, which the slices deliver one atom at a
  time, so each slice is useful alone.

## Alternatives considered

**One strong invariant without atoms.** Rejected: one statement that bypasses a constraint would
lose every fact, and the user could not use the facts that still hold. A helper must never be
the only door (the workspace rule on flexibility and usability).

**Add the constraints to today's invariant.** Rejected: claims would then silently exclude
databases that SQLite can reach, against ADR 0012's rule.

**Bundle the surface's database in S2.** Rejected at first: `db.run` cannot give the proof before
the theorems of D3 exist. Amended 2026-10-22: a check gives the proof for each concrete run, so
S2 bundles the database (D5, amended), and the theorems move to before S4.

## Not decided here

- How elaboration treats a statement that has no theorem for an atom, in a claim over every
  database, when the model describes such a statement (D5, amended).
- Whether the cells of stored generated columns become an atom.
- The model of `PRAGMA ignore_check_constraints` and `writable_schema`.

## Owner decisions

Decided on 2026-10-22, in the design discussion of S2:

1. **The atoms are the primitives**, public, and the two bundles are built from them.
2. **Strong is `Database.Valid`, weak is `Database.Admitted`.**
3. **Foreign keys are an atom outside `Database.Valid`.**
4. **A theorem for each atom**, with conditions on the connection, delivered slice by slice; the
   postponed work is documented, and the guide keeps its scope.
5. **The bundled database in S2, with a checked run** (D5, amended 2026-10-22): the
   surface's `Database` carries its proof of `Database.Valid`, `Database.Raw` is the plain
   database, and the theorems of D3 replace the check before S4.
