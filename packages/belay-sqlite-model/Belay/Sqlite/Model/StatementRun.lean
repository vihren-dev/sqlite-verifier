import Belay.Sqlite.Model.Counters
import Belay.Sqlite.Model.ForeignKeyWrites

set_option doc.verso true

/-! The pieces of one statement's run that {lit}`StatementStep` combines: the unique keys of a
table, the checked write of INSERT and UPDATE, and what running a statement gives, with the run
of a write that checks foreign keys (ADR 0018, D4). -/

namespace Belay.Sqlite.Model

/-- The unique keys of the table at the position in the database's catalog
({name}`Catalog.uniqueKeys`), which every write to it keeps unique. -/
def Database.keys (database : Database) (target : Nat) (table : Table) : List UniqueKey :=
  database.catalog.uniqueKeys target table.shape

/-- Store a write's result when it satisfies the constraints of the given keys and its
rowids are distinct ({name}`LiteralData.rowidsDistinct`), or fail with
{lean}`ExecutionError.constraintViolation` and the input database. -/
def checkedWrite (database : Database) (target : Nat) (keys : List UniqueKey) (result : Table) : Effect :=
  if LiteralData.constraints keys result && LiteralData.rowidsDistinct result then
    .ok (database.setRows target result.rows)
  else .error (.constraintViolation, database)

/-- The outcome of INSERT: SQLite inserts the rows in order, and refuses a rowid alias
that is not an integer before the constraints of its row
({name}`LiteralData.aliasMismatch`), so the first such row is
{lean}`ExecutionError.datatypeMismatch` unless the rows before it already fail; with no
such row, {name}`checkedWrite` of the table with all rows inserted ({lit}`result`, which is
{name}`LiteralData.inserted`). A failure keeps the input database. -/
def insertOutcome (database : Database) (target : Nat) (keys : List UniqueKey) (table : Table)
    (rows : List (List Value)) (result : Table) : Effect :=
  match rows.findIdx? (LiteralData.aliasMismatch table.shape) with
  | some index =>
    let before := LiteralData.inserted table (rows.take index)
    if LiteralData.constraints keys before && LiteralData.rowidsDistinct before then
      .error (.datatypeMismatch, database)
    else .error (.constraintViolation, database)
  | none => checkedWrite database target keys result

/-- What running one statement on a database gives: its effect, whether the model
describes it on the database (the support check), what it does to the counters of its
connection, and for a write that checks foreign keys the rows that it wrote. All read the same
computation of the write or the query (ADR 0024, D2). -/
structure StatementRun where
  /-- The effect of the statement ({lit}`literalStep`). -/
  effect : Effect
  /-- Whether the model describes the statement on the database ({lit}`statementReady`). -/
  ready : Bool
  /-- What the statement does to the counters of the connection, for a success and for a failure
  ({name}`Counts`); the default leaves all three, as every statement except a write does. -/
  counts : Counts := {}
  /-- The rows that a write that checks foreign keys wrote ({name}`KeyRun.written`); none for
  every other statement. -/
  keyRows : Option (List Row) := none

/-- The run of a write whose plain computation gives the effect, the support check and the
counts: the same with foreign keys off, and with them on the run of the keys
({name}`KeyRun`), described when both are. -/
def StatementRun.withKeys (effect : Effect) (ready : Bool) (counts : Counts) : Option KeyRun → StatementRun
  | none => { effect, ready, counts }
  | some run => { effect := run.effect, ready := ready && run.ready, counts := run.counts, keyRows := some run.written }

end Belay.Sqlite.Model
