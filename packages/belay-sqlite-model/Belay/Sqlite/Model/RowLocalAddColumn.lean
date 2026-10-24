import Belay.Sqlite.Model.ExprAppendLaws
import Belay.Sqlite.Model.KeysUniqueAddColumn
import Belay.Sqlite.Model.Resolution.AddColumn
import Belay.Sqlite.Model.Resolution.ReadDefaultLaws
import Belay.Sqlite.Model.RowLocalFrame
import Belay.Sqlite.Model.StatementStep

set_option doc.verso true

/-! The laws of ADD COLUMN for the atoms "not null", "types fit" and "checks hold" (ADR 0022, D3,
slice 3). ADD COLUMN appends a cell to each row of its table ({lit}`Database.addColumn`). The step
fails for a NOT NULL column with a NULL default and for a row that fails a CHECK of the new column
on a table with rows, and the cell is the stored default ({lit}`AddedCell`). The task file of the
slice gives a counterexample for each condition below. {lit}`RowLocalAddColumnTheorems` proves the
three atoms from these laws. -/

namespace Belay.Sqlite.Model

/-- The condition of ADD COLUMN on the width, for all three atoms: if the target holds a table,
each of its rows has one cell for each column ({name}`Table.RowsWide`). Without it the new cell
goes to the position of an old column. A target without a table requires nothing. Today it is an
atom of {lit}`Database.Admitted`, and the model does not prove that the runs keep it. -/
def Database.RowsWideAt (database : Database) (target : Nat) : Prop :=
  ∀ table, database.table target = some table → table.RowsWide

/-- The condition of ADD COLUMN for "checks hold": if the target holds a table, each CHECK
constraint of the table ({name}`CatalogTable.allChecks`) reads only columns below the width of the
table ({name}`Resolved.Expr.readsBelow`). Without it a CHECK that reads a missing column, which
reads NULL and passes, reads the new cell after ADD COLUMN. A resolver fact: the resolver resolves
each CHECK over the columns of its table; {lit}`Catalog.Valid` does not give it. -/
def Database.ChecksReadBelowAt (database : Database) (target : Nat) : Prop :=
  ∀ table, database.table target = some table →
    ∀ check ∈ table.shape.allChecks, check.condition.readsBelow table.shape.columns.length = true

/-- The condition of ADD COLUMN for "types fit", for the given column: if the target holds a table
with rows, the stored default of the column fits its strict type ({name}`strictDefaultFits`).
Without it a STRICT table gets a cell of the wrong type. A resolver fact: the resolver refuses such
a column ({lit}`add-column-strict-type`). -/
def Database.StrictDefaultFitsAt (database : Database) (target : Nat) (column : CatalogColumn) : Prop :=
  ∀ table, database.table target = some table → table.rows ≠ [] → strictDefaultFits column = true

/-- What a successful ADD COLUMN of the column with the default value gives on the table: the
table has no rows, or the default is the read default of the column
({name}`readDefaultValue`), a NOT NULL column has a default other than NULL, and every row with the
default appended passes each CHECK of the new column. -/
def AddedCell (table : Table) (column : CatalogColumn) (value : Value) : Prop :=
  table.rows = [] ∨ (readDefaultValue column = .ok value ∧ (column.notNull = true → value ≠ .null) ∧
    ∀ row ∈ table.rows, ∀ check ∈ column.checks,
      LiteralData.checkHolds { row with values := row.values ++ [value] } check = true)

/-- For every clock value, counters, parameter list, target, column and database: the database of the effect
of {name}`step` for ADD COLUMN is the database, or it is {name}`Database.addColumn` with a value at
a target that holds a table, and the value is an added cell of the table ({name}`AddedCell`).
Proof sketch: case analysis of the steps of {name}`step`; a default that reads the clock succeeds
only on a table without rows, and the other successes passed the three checks. -/
theorem step_addColumn_cases (clock : Int) (counters : Counters) (parameters : List Value) (target : Nat) (column : CatalogColumn)
    (database : Database) :
    effectDatabase (step clock counters parameters (.addColumn target column) database) = database ∨
      ∃ table value, database.table target = some table ∧ AddedCell table column value ∧
        effectDatabase (step clock counters parameters (.addColumn target column) database) =
          database.addColumn target column value := by
  cases found : database.table target with
  | none => left; simp [step, found, effectDatabase]
  | some table =>
    simp only [step, found]
    split
    · split
      · right
        rename_i empty
        exact ⟨table, .null, rfl, .inl (by simpa using empty), rfl⟩
      · left; simp [effectDatabase]
    · split
      · left; simp [effectDatabase]
      · rename_i value read
        split
        · left; simp [effectDatabase]
        · split
          · left; simp [effectDatabase]
          · rename_i nullDefault failing
            right
            by_cases empty : table.rows = []
            · exact ⟨table, value, rfl, .inl empty, rfl⟩
            refine ⟨table, value, rfl, .inr ⟨read, fun flagged same => nullDefault ?_, ?_⟩, rfl⟩
            · simp [flagged, same, empty]
            · intro row member check inChecks
              simp at failing
              exact failing row member check inChecks

/-- For every table with wide rows, column, value, row, position, column and cell: if the row is a
row of the table with the column appended ({name}`Table.appendColumns`), and the new table has the
column and the cell at the position, the row is a row of the table with the stored default
appended, and either the old table has the same column and the old row the same cell at the
position, or the column is the new column and the cell is its stored default
({name}`Value.store` with the affinity of the column). Proof sketch: a position below the width
reads the old column and the old cell; the position of the width reads the new ones; no cell is
past it. -/
theorem Table.appendColumns_cases {table : Table} (wide : table.RowsWide) {column : CatalogColumn} {value : Value}
    {row : Row} (member : row ∈ (table.appendColumns [(column, value)]).rows) {position : Nat}
    {atColumn : CatalogColumn} {atValue : Value}
    (hasColumn : (table.appendColumns [(column, value)]).shape.columns[position]? = some atColumn)
    (hasValue : row.values[position]? = some atValue) :
    ∃ old ∈ table.rows, row = old.appendValues [Value.store column.affinity value] ∧
      ((table.shape.columns[position]? = some atColumn ∧ old.values[position]? = some atValue) ∨
        (atColumn = column ∧ atValue = Value.store column.affinity value)) := by
  simp only [Table.appendColumns, List.map_cons, List.map_nil, List.mem_map] at member hasColumn
  obtain ⟨old, inOld, rfl⟩ := member
  refine ⟨old, inOld, rfl, ?_⟩
  have width := wide old inOld
  simp only [Row.appendValues] at hasValue
  by_cases below : position < table.shape.columns.length
  · rw [List.getElem?_append_left below] at hasColumn
    rw [List.getElem?_append_left (width ▸ below)] at hasValue
    exact .inl ⟨hasColumn, hasValue⟩
  · rw [List.getElem?_append_right (Nat.le_of_not_lt below)] at hasColumn
    rw [List.getElem?_append_right (width ▸ Nat.le_of_not_lt below)] at hasValue
    cases rest : position - table.shape.columns.length with
    | zero => simp_all
    | succ _ => simp_all

/-- For every atom, database, target, column and value: if every table of the database has the
atom, and the atom holds for the table at the target with the column appended
({name}`Table.appendColumns`), every table of the database after {lit}`Database.addColumn` has it.
Proof sketch: the table at the target is the old table with the column appended
({name}`Database.table_addColumn`), every other table is the same
({name}`Database.table_addColumn_other`), and a target without a table has no table after the
ADD COLUMN either. -/
theorem Database.EachTable.addColumn {atom : Table → Prop} {database : Database} (every : database.EachTable atom)
    (target : Nat) (column : CatalogColumn) (value : Value)
    (appended : ∀ table, database.table target = some table → atom (table.appendColumns [(column, value)])) :
    (database.addColumn target column value).EachTable atom := by
  intro position table present
  by_cases same : position = target
  · subst same
    cases found : database.table position with
    | none =>
      exfalso
      have absent : database.catalog.tableAt position = none := by simpa [Database.table] using found
      have still : (database.catalog.addColumn position column).tableAt position = none := by
        unfold Catalog.addColumn
        split
        · rename_i name shape entry
          simp [Catalog.tableAt, entry] at absent
        all_goals exact absent
      simp [Database.table, Database.addColumn, still] at present
    | some old =>
      rw [Database.table_addColumn column value found, Option.some.injEq] at present
      subst present
      exact appended old found
  · rw [Database.table_addColumn_other database column value same] at present
    exact every position table present

end Belay.Sqlite.Model
