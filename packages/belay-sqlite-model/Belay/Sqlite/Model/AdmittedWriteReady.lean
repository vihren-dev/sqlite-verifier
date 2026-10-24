import Belay.Sqlite.Model.DatabaseFactChecks
import Belay.Sqlite.Model.StatementStep

set_option doc.verso true

/-! What the support check of a plain write gives (ADR 0022, D3, slice 4). The statement theorems
of "rows in range", "rows wide", "rows stored" and "rows aliased" assume that the run of the
statement is ready ({lit}`StatementRun.ready`). For INSERT, UPDATE and an upsert without rules, the
run is ready only when the check of the data domain of the write passes ({lit}`LiteralData.insertReady`,
{lit}`LiteralData.updateReady` and {lit}`LiteralData.upsertReady`). These lemmas read that check
from the run. -/

namespace Belay.Sqlite.Model

/-- For every clock value, counters, parameter list, plain INSERT and database, and every table at the
target: if the run of {name}`runStatement` is ready, the check {name}`LiteralData.insertReady` passes for
the table, the supplied cells and the table with the rows inserted. Proof sketch: without rules the
support check of the run is a conjunction that starts with this check. -/
theorem runStatement_insert_ready {clock : Int} {counters : Counters} {parameters : List Value} {target : Nat}
    {rows : List (List Resolved.Cell)} {returning : List (Resolved.Expr × String)} {subqueries : List Resolved.Query}
    {database : Database} {table : Table}
    (ready : (runStatement clock counters parameters (.insert target rows returning subqueries none) database).ready = true)
    (found : database.table target = some table) :
    LiteralData.insertReady (database.keys target table) table
      (Resolved.rowsAt (Resolved.statementContext clock counters parameters database subqueries) table.shape.columns rows)
      (LiteralData.inserted table (Resolved.rowsAt (Resolved.statementContext clock counters parameters database subqueries)
        table.shape.columns rows)) = true := by
  simp only [runStatement, Option.map_none, StatementRun.withKeys, found, Bool.and_eq_true] at ready
  exact ready.1.1.1

/-- For every clock value, counters, parameter list, plain UPDATE and database, and every table at the
target: if the run of {name}`runStatement` is ready, the check {name}`LiteralData.updateReady` passes for
the table, the assignments and the updated table. The statement does not depend on
{name}`LiteralData.updateMismatch`. Proof sketch: without rules the support check of the run is a
conjunction that starts with this check. -/
theorem runStatement_update_ready {clock : Int} {counters : Counters} {parameters : List Value} {target : Nat}
    {assignments : List (Nat × Resolved.Expr)} {filter : Option Resolved.Expr}
    {returning : List (Resolved.Expr × String)} {subqueries : List Resolved.Query}
    {database : Database} {table : Table}
    (ready : (runStatement clock counters parameters (.update target assignments filter returning subqueries none)
      database).ready = true) (found : database.table target = some table) :
    LiteralData.updateReady (database.keys target table) table assignments
      (LiteralData.updated (Resolved.statementContext clock counters parameters database subqueries) table assignments
        filter) = true := by
  simp only [runStatement, Option.map_none, StatementRun.withKeys, found, Bool.and_eq_true] at ready
  exact ready.1.1

/-- For every clock value, counters, parameter list, upsert without rules and database, and every table at
the target: if the run of {name}`runStatement` is ready, the check {name}`LiteralData.upsertReady` passes for
the table, the clauses, the supplied cells and the reached rows ({name}`LiteralData.upsertSteps`).
Proof sketch: without rules the support check of the run is a conjunction that starts with this
check. -/
theorem runStatement_upsert_ready {clock : Int} {counters : Counters} {parameters : List Value} {target : Nat}
    {rows : List (List Resolved.Cell)} {clauses : List Resolved.ConflictClause}
    {returning : List (Resolved.Expr × String)} {algorithm : Option ConflictAlgorithm}
    {subqueries : List Resolved.Query} {database : Database} {table : Table}
    (ready : (runStatement clock counters parameters (.upsert target rows clauses returning algorithm subqueries none)
      database).ready = true) (found : database.table target = some table) :
    LiteralData.upsertReady (database.keys target table) table clauses
      (Resolved.rowsAt (Resolved.statementContext clock counters parameters database subqueries) table.shape.columns rows)
      (LiteralData.upsertSteps (Resolved.statementContext clock counters parameters database subqueries)
        (database.keys target table) (database.catalog.writePolicy target table.shape algorithm) clauses table
        (Resolved.rowsAt (Resolved.statementContext clock counters parameters database subqueries) table.shape.columns rows))
      = true := by
  simp only [runStatement, Option.map_none, StatementRun.withKeys, found, Bool.and_eq_true] at ready
  exact ready.1.1.1

/-- For every supplied row of cells and table columns: if each cell in {lit}`columns.zip values` passes
{name}`LiteralData.storedForm`, each cell is stored for the column at its position. Proof sketch: a
position with a column and a cell is a member of the zip. -/
theorem storedForm_stored {columns : List CatalogColumn} {values : List Value}
    (stored : (columns.zip values).all (fun (column, value) => LiteralData.storedForm column.affinity value) = true) :
    ∀ (position : Nat) (column : CatalogColumn) (value : Value), columns[position]? = some column →
      values[position]? = some value → Value.store column.affinity value = value := by
  intro position column value atColumn atCell
  have pair : (columns.zip values)[position]? = some (column, value) := List.getElem?_zip_eq_some.mpr ⟨atColumn, atCell⟩
  have form := List.all_eq_true.mp stored (column, value) (List.mem_of_getElem? pair)
  simpa [LiteralData.storedForm] using form

/-- The parts of {name}`LiteralData.insertReady` that the table atoms use. For every keys, table, supplied
rows and result table: if the check passes, then the entry of the table passes
{name}`LiteralData.aliasReady`, each supplied row has one cell for each column and is stored for the columns,
and the rowids of the result are signed 64-bit integers ({name}`Table.RowidsInRange`). Proof sketch: the
check is a conjunction of these tests. -/
theorem insertReady_parts {keys : List UniqueKey} {table result : Table} {rows : List (List Value)}
    (ready : LiteralData.insertReady keys table rows result = true) :
    LiteralData.aliasReady table.shape = true ∧
      (∀ values ∈ rows, values.length = table.shape.columns.length) ∧
      (∀ values ∈ rows, ∀ (position : Nat) (column : CatalogColumn) (value : Value),
        table.shape.columns[position]? = some column → values[position]? = some value →
          Value.store column.affinity value = value) ∧ result.RowidsInRange := by
  simp only [LiteralData.insertReady, Bool.and_eq_true, List.all_eq_true, beq_iff_eq] at ready
  obtain ⟨⟨⟨_, alias⟩, supplied⟩, bounded⟩ := ready
  exact ⟨alias, fun values member => (supplied values member).1,
    fun values member => storedForm_stored (List.all_eq_true.mpr (supplied values member).2),
    (Table.rowidsInRange_iff result).mp (List.all_eq_true.mpr bounded)⟩

/-- The parts of {name}`LiteralData.updateReady` that the table atoms use. For every keys, table,
assignments and result table: if the check passes, then the entry of the table passes
{name}`LiteralData.aliasReady`, and the rowids of the result are signed 64-bit integers. Proof sketch: the
check is a conjunction of these tests. -/
theorem updateReady_parts {keys : List UniqueKey} {table result : Table} {assignments : List (Nat × Resolved.Expr)}
    (ready : LiteralData.updateReady keys table assignments result = true) :
    LiteralData.aliasReady table.shape = true ∧ result.RowidsInRange := by
  simp only [LiteralData.updateReady, Bool.and_eq_true, List.all_eq_true] at ready
  obtain ⟨⟨⟨_, alias⟩, _⟩, bounded⟩ := ready
  exact ⟨alias, (Table.rowidsInRange_iff result).mp (List.all_eq_true.mpr bounded)⟩

/-- The parts of {name}`LiteralData.upsertReady` that the table atoms use. For every keys, table, clauses,
supplied rows and reached rows: if the check passes, then the entry of the table passes
{name}`LiteralData.aliasReady`, each supplied row has one cell for each column and is stored for the columns,
and the reached rows are bounded ({name}`LiteralData.upsertBounded`). Proof sketch: the check is a
conjunction of these tests. -/
theorem upsertReady_parts {keys : List UniqueKey} {table : Table} {clauses : List Resolved.ConflictClause}
    {rows : List (List Value)} {steps : List LiteralData.UpsertStep}
    (ready : LiteralData.upsertReady keys table clauses rows steps = true) :
    LiteralData.aliasReady table.shape = true ∧
      (∀ values ∈ rows, values.length = table.shape.columns.length) ∧
      (∀ values ∈ rows, ∀ (position : Nat) (column : CatalogColumn) (value : Value),
        table.shape.columns[position]? = some column → values[position]? = some value →
          Value.store column.affinity value = value) ∧ LiteralData.upsertBounded steps = true := by
  simp only [LiteralData.upsertReady, Bool.and_eq_true, List.all_eq_true, beq_iff_eq] at ready
  obtain ⟨⟨⟨⟨_, alias⟩, supplied⟩, _⟩, bounded⟩ := ready
  exact ⟨alias, fun values member => (supplied values member).1,
    fun values member => storedForm_stored (List.all_eq_true.mpr (supplied values member).2), bounded⟩

end Belay.Sqlite.Model
