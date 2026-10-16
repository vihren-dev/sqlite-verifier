import Belay.Sqlite.RowUpdate
import Belay.Sqlite.Resolution.ConflictForm
import Belay.Sqlite.Execution

set_option doc.verso true

/-! The {lit}`ON CONFLICT` clauses of INSERT (ADR 0012, amendment 4, slice 5c), checked
on native SQLite 3.51.0: the proposed row, the first clause whose target key has a
conflicting row ({lit}`handlingClause`), and {lit}`DO UPDATE` of that row, which is
checked with ABORT whatever the conflict algorithms say. {lit}`UpsertRun` processes the
rows with the clauses and the conflict algorithms of slice 5d. -/

namespace Belay.Sqlite
namespace LiteralData

/-- The row that INSERT proposes for the cells: the rowid of {name}`newRowid` and the
cells of {name}`newCells`, which {name}`insertRow` appends. It is also the row that
{lit}`excluded` reads, so a NULL alias reads the new rowid. -/
def proposedRow (table : Table) (values : List Value) : Row :=
  { rowid := newRowid table values, values := newCells table values (newRowid table values) }

/-- The first row of the table that conflicts with the proposed row on one of the keys
({name}`keyEqual`), or none. -/
def conflictingRow (keys : List (List Nat)) (table : Table) (proposed : Row) : Option Row :=
  table.rows.find? fun row => keys.any fun key => keyEqual key row proposed

/-- The keys that a clause checks: its target key, or every key for a clause without
target. -/
def clauseKeys (keys : List (List Nat)) (clause : Resolved.ConflictClause) : List (List Nat) :=
  match clause.target with
  | some key => [key]
  | none => keys

/-- The first clause, in written order, whose keys ({name}`clauseKeys`) have a row that
conflicts with the proposed row, with that row; none when no clause has one. -/
def handlingClause (keys : List (List Nat)) (clauses : List Resolved.ConflictClause) (table : Table)
    (proposed : Row) : Option (Resolved.ConflictClause × Row) :=
  clauses.findSome? fun clause => (conflictingRow (clauseKeys keys clause) table proposed).map (clause, ·)

/-- The table with each row of the old row's rowid replaced by the new row. Rowids are
distinct in a valid table, so one row changes; the order of rows stays. -/
def replaceRow (table : Table) (old new : Row) : Table :=
  { table with rows := table.rows.map fun row => if row.rowid == old.rowid then new else row }

/-- Whether an updated row has a rowid alias cell that SQLite refuses with
{lit}`datatype mismatch`: the table has an alias and the row has no integer there. -/
def aliasCellMismatch (alias : Option Nat) (row : Row) : Bool :=
  match alias with
  | none => false
  | some position => match row.values[position]? with
    | some (.integer _) => false
    | some .null | some (.real _) | some (.text _) | some (.blob _) | none => true

/-- The table after a write of one row, with the row that {lit}`RETURNING` reads, when
the table passes {name}`constraints` and {name}`rowidsDistinct`; otherwise the unique or
NOT NULL failure. -/
def checkedRow (keys : List (List Nat)) (next : Table) (written : Row) :
    Except ExecutionError (Table × Option Row) :=
  if constraints keys next && rowidsDistinct next then .ok (next, some written) else .error .constraintViolation

/-- The {lit}`DO UPDATE` of an existing row: the assignments and the filter read the
existing row followed by the proposed row. A filter that is not true skips the row; the
new row takes the rowid of {name}`movedRowid`, and a non-integer alias is
{lit}`datatype mismatch`; the result is checked by {name}`checkedRow`. -/
def updateExisting (keys : List (List Nat)) (table : Table) (assignments : List (Nat × Resolved.Expr))
    (filter : Option Resolved.Expr) (existing proposed : Row) : Except ExecutionError (Table × Option Row) :=
  let context := existing.values ++ proposed.values
  if !(filter.all fun condition => Resolved.truthy (condition.eval context)) then .ok (table, none) else
  let changed := movedRowid table.shape.rowidAlias (assignFrom table.shape.columns assignments context existing)
  if aliasCellMismatch table.shape.rowidAlias changed then .error .datatypeMismatch
  else checkedRow keys (replaceRow table existing changed) changed

end LiteralData
end Belay.Sqlite
