import Belay

/-! A fixture of `tests/surface_guide_test.py`: checks of the model functions that `db!` uses for
its errors. They cover `ExecutionError.message` (`Model/ExecutionMessages.lean`) for each
constructor, `LiteralData.tableFailures` (`Model/TableFailure.lean`) and `keyCandidates`
(`Model/KeyCandidates.lean`), from which `failingConstraints` names a constraint,
`Resolved.Statement.writeRules` (`Model/FailingConstraints.lean`) of resolved INSERTs,
`Database.failingAtom?` (`Model/ValidityFailure.lean`) on plain databases that are
not valid, `ValidityAtom.name` for each atom, and the term or error that `db!` gives for a
database (`databaseTerm` and `invalidDatabaseMessage` of `Belay/Sqlite/DbBang.lean`). The file fails to elaborate when a check fails. -/

open Belay.Sqlite
open Belay.Sqlite.Model (ExecutionError ValidityAtom LiteralData.tableFailures keyCandidates noCandidateMessage
  triggerOrKeyConstraintMessage functionFailedMessage unmodeledHere)

-- SQLite 3.51's texts, where the model keeps what the message says.
#guard (ExecutionError.prepare (.expression (.noSuchColumn (name! "nmae")))).message 0 {} [] .commit {} ==
  "no such column: nmae"
#guard ExecutionError.transactionAlreadyActive.message 0 {} [] .begin {} == "cannot start a transaction within a transaction"
#guard ExecutionError.noActiveTransaction.message 0 {} [] .commit {} == "cannot commit - no transaction is active"
#guard ExecutionError.noActiveTransaction.message 0 {} [] .rollback {} == "cannot rollback - no transaction is active"
#guard ExecutionError.integerOverflow.message 0 {} [] .commit {} == "integer overflow"
#guard ExecutionError.datatypeMismatch.message 0 {} [] .commit {} == "datatype mismatch"
#guard ExecutionError.nullColumnDefault.message 0 {} [] .commit {} == "Cannot add a NOT NULL column with default value NULL"
#guard ExecutionError.nonConstantColumnDefault.message 0 {} [] .commit {} == "Cannot add a column with non-constant default"
#guard ExecutionError.checkColumnDefault.message 0 {} [] .commit {} == "CHECK constraint failed"
-- The texts that are not SQLite's message for the statement. A write with rules (a trigger or a
-- foreign key) does not name the constraint; a statement that does not fail a constraint has no
-- candidate, which names a defect.
#guard ExecutionError.constraintViolation.message 0 {} [] (.insert 0 [] [] [] (some { depth := 0, keys := true })) {} ==
  "constraint failed; the model does not name the constraint that fails in a write that can fire a trigger " ++
    "or that checks foreign keys. Run the statement in the sqlite3 shell to see SQLite's message"
#guard ExecutionError.constraintFail.message 0 {} [] (.update 0 [] none [] [] (some { depth := 0, keys := true })) {} ==
  triggerOrKeyConstraintMessage
#guard ExecutionError.constraintRollback.message 0 {} [] .commit {} == noCandidateMessage
#guard ExecutionError.functionError.message 0 {} [] .commit {} == functionFailedMessage
#guard ExecutionError.unmodeled.message 0 {} [] .commit {} == unmodeledHere

/-- Whether the last statement of the script, resolved after the run of the statements before it
on the empty database (`resolveStatement`), has rules (`Resolved.Statement.writeRules` of
`Model/FailingConstraints.lean`); none when it does not resolve. The theorems of
`failingConstraints` hold for a statement without rules, so these checks tie that condition to
resolution. -/
def lastHasRules (script : Script) : Option Bool :=
  match script.statements.reverse with
  | [] => none
  | (last, _) :: earlier =>
    match Belay.Sqlite.Model.resolveStatement runContext
        (Database.Raw.run {} ⟨earlier.reverse⟩).connection.resolveState last with
    | .ok (resolved, _) => some resolved.writeRules.isSome
    | .error _ => none

-- A plain INSERT has no rules, also with foreign keys on for a table without foreign keys. An
-- INSERT into a table with an INSERT trigger has rules, also when its WHEN is always false.
#guard lastHasRules (sql r"CREATE TABLE plain (a NOT NULL); INSERT INTO plain VALUES (NULL)") == some false
#guard lastHasRules (sql r"PRAGMA foreign_keys = ON; CREATE TABLE plain (a NOT NULL);
  INSERT INTO plain VALUES (NULL)") == some false
#guard lastHasRules (sql r"CREATE TABLE watched (a); CREATE TABLE seen (a);
  CREATE TRIGGER watched_never AFTER INSERT ON watched WHEN 0 BEGIN INSERT INTO seen VALUES (new.a); END;
  INSERT INTO watched VALUES (1)") == some true

/-- A table `t(a, b NOT NULL)` with a PRIMARY KEY on `a`, and two rows. -/
def pair : Database := db! r"CREATE TABLE t (a PRIMARY KEY, b NOT NULL); INSERT INTO t VALUES (1, 'x'), (2, 'y')"

/-- The rows of `pair` with a NULL in the NOT NULL column `b`. -/
def nullInNotNull : Database.Raw :=
  pair.raw.setRows 0 [{ rowid := 1, values := [1, .null] }, { rowid := 2, values := [2, "y"] }]

/-- The rows of `pair` with the key `a` 1 twice. -/
def duplicateKey : Database.Raw :=
  pair.raw.setRows 0 [{ rowid := 1, values := [1, "x"] }, { rowid := 2, values := [1, "y"] }]

/-- The rows of `pair` with the rowid 1 twice. -/
def duplicateRowid : Database.Raw :=
  pair.raw.setRows 0 [{ rowid := 1, values := [1, "x"] }, { rowid := 1, values := [2, "y"] }]

/-- A STRICT table `s(a INTEGER CHECK (a < 5))` with one row. -/
def strictChecked : Database := db! r"CREATE TABLE s (a INTEGER CHECK (a < 5)) STRICT; INSERT INTO s VALUES (1)"

/-- The row of `strictChecked` with `7`, an integer that fails the CHECK constraint only. -/
def checkOnly : Database.Raw := strictChecked.raw.setRows 0 [{ rowid := 1, values := [7] }]

/-- The row of `strictChecked` with `1.5`, a real that does not fit the STRICT type and passes
the CHECK constraint. -/
def typeOnly : Database.Raw := strictChecked.raw.setRows 0 [{ rowid := 1, values := [.real (1.5 : Float).toBits] }]

/-- The row of `strictChecked` with `'x'`, a text that fails both the STRICT type and the CHECK
constraint, because a text is greater than every number. -/
def checkAndType : Database.Raw := strictChecked.raw.setRows 0 [{ rowid := 1, values := ["x"] }]

/-- `pair` with no list of rows for its table. -/
def unshaped : Database.Raw := { pair.raw with rows := [] }

-- The failures of a table, in SQLite's order of checks: NOT NULL, STRICT, CHECK, rowid, keys.
/-- The failures of the table at position 0 of the database, with its keys. -/
def failuresOf (database : Database.Raw) : Option (List Belay.Sqlite.Model.TableFailure) :=
  (database.table 0).map fun table => LiteralData.tableFailures (database.keys 0 table) table
#guard failuresOf pair.raw == some []
#guard failuresOf nullInNotNull == some [.notNull 1]
#guard failuresOf duplicateKey == some [.keys [0]]
#guard failuresOf duplicateRowid == some [.rowid]
#guard failuresOf checkAndType == some [.strictType 0 "x", .check "a < 5"]

-- The keys that SQLite may name among the failing keys: the PRIMARY KEY of a rowid alias, the
-- newest unique index, the UNIQUE constraint written last, keys declared REPLACE after the
-- others, and both a PRIMARY KEY that is not the alias and the last UNIQUE constraint.
#guard keyCandidates [.primaryKey, .unique 0] { columns := [], primaryKey := [0], rowidAlias := some 0 } [0, 1] == [0]
#guard keyCandidates [.unique 0, .index 3, .index 5] { columns := [] } [0, 1, 2] == [2]
#guard keyCandidates [.unique 0, .unique 1] { columns := [] } [0, 1] == [1]
#guard keyCandidates [.unique 0, .unique 1] { columns := [], uniqueAlgorithms := [none, some .replace] } [0, 1] == [0]
#guard keyCandidates [.unique 0, .unique 1] { columns := [], uniqueAlgorithms := [none, some .replace] } [1] == [1]
#guard keyCandidates [.primaryKey, .unique 0] { columns := [], primaryKey := [1] } [0, 1] == [1, 0]

-- The first atom that fails, in field order, and none for a valid database. `checkAndType`
-- fails two atoms, so it checks that ChecksHold comes before TypesFit.
#guard pair.raw.failingAtom? Profile.pinned == none
#guard strictChecked.raw.failingAtom? Profile.pinned == none
#guard nullInNotNull.failingAtom? Profile.pinned == some .notNull
#guard duplicateKey.failingAtom? Profile.pinned == some .keysUnique
#guard duplicateRowid.failingAtom? Profile.pinned == some .rowidsDistinct
#guard checkOnly.failingAtom? Profile.pinned == some .checksHold
#guard typeOnly.failingAtom? Profile.pinned == some .typesFit
#guard checkAndType.failingAtom? Profile.pinned == some .checksHold
#guard unshaped.failingAtom? Profile.pinned == some .rowsShaped
example : ¬nullInNotNull.Valid Profile.pinned := by
  rw [← Belay.Sqlite.Model.Database.failingAtom?_eq_none_iff]; decide +kernel

/-- Every atom, in the order of `ValidityAtom`. -/
def everyAtom : List ValidityAtom :=
  [.catalog, .rowsShaped, .rowidsDistinct, .rowidsInRange, .rowsWide, .rowsStored, .rowsAliased, .notNull,
    .checksHold, .typesFit, .keysUnique]

-- Each atom has its own name, and each name is a declaration of the model.
#guard (everyAtom.map ValidityAtom.name).eraseDups.length == 11
open Lean in
#eval show MetaM Unit from do
  for atom in everyAtom do
    unless (← getEnv).contains (`Belay.Sqlite.Model ++ atom.name.toName) do
      throwError "{atom.name} is not a declaration in Belay.Sqlite.Model; correct ValidityAtom.name"

-- The term or the error of `db!`: the error names the atom, and a valid database gives its term.
#guard match databaseTerm nullInNotNull with
  | .error message => message == invalidDatabaseMessage .notNull
  | .ok _ => false
#guard match databaseTerm pair.raw with
  | .ok term => term == databaseExpr pair.raw
  | .error _ => false
#guard invalidDatabaseMessage .notNull == "the database that db! builds is not valid: Database.NotNull does not " ++
  "hold. The model's statements keep a database valid, so this is a defect of the model; report the SQL text " ++
  "to the maintainers of the model"
