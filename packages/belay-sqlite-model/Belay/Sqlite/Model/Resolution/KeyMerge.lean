import Belay.Sqlite.Model.Resolution.Resolved

set_option doc.verso true

/-! The keys of CREATE TABLE as SQLite's {lit}`sqlite3CreateIndex` builds them, checked on
native SQLite 3.51.0: a UNIQUE or PRIMARY KEY constraint (other than a rowid alias) with
the columns, in order, of an earlier one is the same index, so the table keeps one key.
Its {lit}`ON CONFLICT` algorithm is the explicit one of the two, and two different
explicit algorithms are SQLite's prepare error
{lit}`conflicting ON CONFLICT clauses specified`. -/

namespace Belay.Sqlite.Model

/-- The algorithm of two constraints that SQLite merges into one index: the explicit one,
the same one twice, or {name}`ExprError.conflictingAlgorithms` for two different
explicit ones. -/
def mergeAlgorithm (first second : Option ConflictAlgorithm) : Except ExprError (Option ConflictAlgorithm) :=
  match first, second with
  | none, other => .ok other
  | some algorithm, none => .ok (some algorithm)
  | some algorithm, some other => if algorithm = other then .ok (some algorithm) else .error .conflictingAlgorithms

/-- Add a UNIQUE key with its algorithm. A key with the columns, in order, of the primary
key (when it is no rowid alias) or of an earlier UNIQUE key is that key, with the merged
algorithm ({name}`mergeAlgorithm`); any other key is appended. -/
def addUniqueKey (table : CatalogTable) (positions : List Nat) (algorithm : Option ConflictAlgorithm) :
    Except ExprError CatalogTable :=
  if table.rowidAlias.isNone && table.primaryKey == positions then do
    let merged ← mergeAlgorithm table.primaryKeyAlgorithm algorithm
    .ok { table with primaryKeyAlgorithm := merged }
  else match table.uniqueKeys.idxOf? positions with
    | some index => do
      let merged ← mergeAlgorithm (table.uniqueAlgorithm index) algorithm
      .ok { table with uniqueAlgorithms := table.keyedUniqueAlgorithms.set index merged }
    | none => .ok { table with uniqueKeys := table.uniqueKeys ++ [positions],
                               uniqueAlgorithms := table.keyedUniqueAlgorithms ++ [algorithm] }

/-- Set the primary key with its rowid alias, direction and algorithm. A primary key that
is no rowid alias, with the columns, in order, of an earlier UNIQUE key, takes that key's
place, with the merged algorithm ({name}`mergeAlgorithm`) and the ascending direction of
that earlier index, which SQLite keeps also for {lit}`PRIMARY KEY DESC`. The keys before it
({name}`CatalogTable.uniqueBeforePrimary`) are the UNIQUE keys written before it, or those
before the key that it takes the place of. -/
def setPrimaryKey (table : CatalogTable) (positions : List Nat) (alias : Option Nat) (descending : Bool)
    (algorithm : Option ConflictAlgorithm) : Except ExprError CatalogTable :=
  let keyed := { table with primaryKey := positions, rowidAlias := alias, primaryKeyDescending := descending,
                            primaryKeyAlgorithm := algorithm,
                            uniqueBeforePrimary := if alias.isSome then 0 else table.uniqueKeys.length }
  match alias, table.uniqueKeys.idxOf? positions with
  | none, some index => do
    let merged ← mergeAlgorithm (table.uniqueAlgorithm index) algorithm
    .ok { keyed with primaryKeyDescending := false, primaryKeyAlgorithm := merged, uniqueBeforePrimary := index,
                     uniqueKeys := table.uniqueKeys.eraseIdx index,
                     uniqueAlgorithms := table.keyedUniqueAlgorithms.eraseIdx index }
  | none, none | some _, _ => .ok keyed

end Belay.Sqlite.Model
