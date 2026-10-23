import Belay.Sqlite.Model.RowLocalAddColumn

set_option doc.verso true

/-! The theorems of the atoms "not null", "types fit" and "checks hold" (ADR 0022, D3, slice 3) for
ADD COLUMN. Each atom has the condition of {lit}`RowLocalAddColumn` for its own reading of the new
cell, and a table-level law, a database-level law, and the statement theorem. The conditions are
necessary: the examples of the slice ({lit}`RowLocalExamples`) show a database that satisfies the
atom before and not after ADD COLUMN, for each condition left out. -/

namespace Belay.Sqlite.Model

/-- For every table, column and value: if the table satisfies {name}`Table.NotNull`, its rows are
wide, and the value is an added cell ({name}`AddedCell`), the table with the column appended
satisfies {name}`Table.NotNull`. Proof sketch: an old position has the old column and the old
cell ({name}`Table.appendColumns_cases`); the new position holds the stored default, which is the
default ({name}`readDefaultValue_stored`), and it is not NULL when the column is NOT NULL. -/
theorem Table.NotNull.appendColumn {table : Table} (notNull : table.NotNull) (wide : table.RowsWide)
    {column : CatalogColumn} {value : Value} (added : AddedCell table column value) :
    (table.appendColumns [(column, value)]).NotNull := by
  intro row member position atColumn atValue hasColumn hasValue flagged
  obtain ⟨old, inOld, rfl, cases⟩ := Table.appendColumns_cases wide member hasColumn hasValue
  rcases cases with ⟨oldColumn, oldCell⟩ | ⟨rfl, rfl⟩
  · exact notNull old inOld position atColumn atValue oldColumn oldCell flagged
  · rcases added with empty | ⟨read, nullOk, _⟩
    · simp [empty] at inOld
    · rw [readDefaultValue_stored _ _ read]
      exact nullOk flagged

/-- For every table, column and value: if the table satisfies {name}`Table.TypesFit`, its rows are
wide, the stored default fits the strict type when the table has rows
({name}`strictDefaultFits`), and the value is an added cell ({name}`AddedCell`), the table with the
column appended satisfies {name}`Table.TypesFit`. Proof sketch: an old position is as in
{name}`Table.NotNull.appendColumn`; the new cell is the default, and
{name}`strictDefaultFits` says that it fits. -/
theorem Table.TypesFit.appendColumn {table : Table} (fits : table.TypesFit) (wide : table.RowsWide)
    {column : CatalogColumn} {value : Value} (strict : table.rows ≠ [] → strictDefaultFits column = true)
    (added : AddedCell table column value) : (table.appendColumns [(column, value)]).TypesFit := by
  intro row member position atColumn atValue hasColumn hasValue
  obtain ⟨old, inOld, rfl, cases⟩ := Table.appendColumns_cases wide member hasColumn hasValue
  rcases cases with ⟨oldColumn, oldCell⟩ | ⟨rfl, rfl⟩
  · exact fits old inOld position atColumn atValue oldColumn oldCell
  · rcases added with empty | ⟨read, _, _⟩
    · simp [empty] at inOld
    · rw [readDefaultValue_stored _ _ read]
      have fitting := strict (List.ne_nil_of_mem inOld)
      simp only [strictDefaultFits, read] at fitting
      cases kind : atColumn.strictType <;> simp_all

/-- For every table, column and value: the CHECK constraints of the table with the column
appended ({name}`CatalogTable.allChecks`) are those of the old columns, those of the new column,
and those of the table. Proof sketch: unfold the definition; the columns are appended. -/
theorem Table.allChecks_appendColumn (table : Table) (column : CatalogColumn) (value : Value) :
    (table.appendColumns [(column, value)]).shape.allChecks =
      table.shape.columns.flatMap (·.checks) ++ column.checks ++ table.shape.checks := by
  simp [Table.appendColumns, CatalogTable.allChecks, List.flatMap_append]

/-- For every table, column and value: if the table satisfies {name}`Table.ChecksHold`, its rows
are wide, each of its CHECK constraints reads only columns below its width
({name}`Resolved.Expr.readsBelow`), and the value is an added cell ({name}`AddedCell`), the table
with the column appended satisfies {name}`Table.ChecksHold`. Proof sketch: a CHECK of the old table
ignores the appended cell ({name}`Resolved.Expr.eval_append`); a CHECK of the new column holds on
the row with the default appended, by the added cell, and the stored default is the default
({name}`readDefaultValue_stored`). -/
theorem Table.ChecksHold.appendColumn {table : Table} (holds : table.ChecksHold) (wide : table.RowsWide)
    (reads : ∀ check ∈ table.shape.allChecks, check.condition.readsBelow table.shape.columns.length = true)
    {column : CatalogColumn} {value : Value} (added : AddedCell table column value) :
    (table.appendColumns [(column, value)]).ChecksHold := by
  intro row member check inChecks
  simp only [Table.appendColumns, List.map_cons, List.map_nil, List.mem_map] at member
  obtain ⟨old, inOld, rfl⟩ := member
  rw [Table.allChecks_appendColumn, List.mem_append, List.mem_append] at inChecks
  rcases inChecks with (oldColumns | newColumn) | tableCheck
  · have oldCheck : check ∈ table.shape.allChecks := by
      unfold CatalogTable.allChecks
      exact List.mem_append_left _ oldColumns
    have same := Resolved.Expr.eval_append (.plain 0) (Resolved.EvalContext.plain_rowFree 0) old.values
      [Value.store column.affinity value] (Nat.le_of_eq (wide old inOld).symm) (reads check oldCheck)
    simpa [LiteralData.checkHolds, Row.appendValues, same] using holds old inOld check oldCheck
  · rcases added with empty | ⟨read, _, newHolds⟩
    · simp [empty] at inOld
    · simpa [Row.appendValues, readDefaultValue_stored column value read] using newHolds old inOld check newColumn
  · have oldCheck : check ∈ table.shape.allChecks := by
      unfold CatalogTable.allChecks
      exact List.mem_append_right _ tableCheck
    have same := Resolved.Expr.eval_append (.plain 0) (Resolved.EvalContext.plain_rowFree 0) old.values
      [Value.store column.affinity value] (Nat.le_of_eq (wide old inOld).symm) (reads check oldCheck)
    simpa [LiteralData.checkHolds, Row.appendValues, same] using holds old inOld check oldCheck

/-- For every atom, clock value, parameter list, ADD COLUMN, column and database: if every table of
the database has the atom, and the atom holds for the table at the target with the column and
every added cell appended, the effect of {name}`runStatement` satisfies "every table has the atom"
({name}`Effect.Satisfies`): the database of a success and that of an error with
{name}`ExecutionError.constraintFail` have it, and any other error requires nothing. Proof
sketch: every error keeps the database, and a success is
{lit}`Database.addColumn` of an added cell ({name}`step_addColumn_cases`), which
{name}`Database.EachTable.addColumn` handles. -/
theorem runStatement_addColumn_rowLocal {atom : Table → Prop} (clock : Int) (parameters : List Value)
    (target : Nat) (column : CatalogColumn) {database : Database} (every : database.EachTable atom)
    (appended : ∀ table value, database.table target = some table → AddedCell table column value →
      atom (table.appendColumns [(column, value)])) :
    (runStatement clock parameters (.addColumn target column) database).effect.Satisfies
      fun after => after.EachTable atom := by
  simp only [runStatement]
  rcases step_addColumn_cases clock parameters target column database with kept | ⟨table, value, found, added, eq⟩
  · exact Effect.satisfies_of_database every kept
  · refine Effect.satisfies_of_effectDatabase ?_
    show (effectDatabase _).EachTable atom
    rw [eq]
    exact every.addColumn target column value fun other present => by
      rw [found, Option.some.injEq] at present
      subst present
      exact appended table value found added

/-- The theorem of "not null" for ADD COLUMN, for every clock value, parameter list, target,
column and database: if the database satisfies {name}`Database.NotNull` and the rows of the table
at the target are wide ({name}`Database.RowsWideAt`), the effect of {name}`runStatement` satisfies
{name}`Database.NotNull` ({name}`Effect.Satisfies`): the database of a success and that of an error
with {name}`ExecutionError.constraintFail` have it, and any other error requires nothing. It assumes
nothing about the other atoms or the support check. Proof sketch:
{name}`runStatement_addColumn_rowLocal` with {name}`Table.NotNull.appendColumn`. -/
theorem runStatement_addColumn_notNull (clock : Int) (parameters : List Value) (target : Nat)
    (column : CatalogColumn) {database : Database} (notNull : database.NotNull)
    (wide : database.RowsWideAt target) :
    (runStatement clock parameters (.addColumn target column) database).effect.Satisfies Database.NotNull :=
  runStatement_addColumn_rowLocal clock parameters target column notNull fun table _ found added =>
    (notNull _ table found).appendColumn (wide table found) added

/-- The theorem of "types fit" for ADD COLUMN, for every clock value, parameter list, target,
column and database: if the database satisfies {name}`Database.TypesFit`, the rows of the table at
the target are wide ({name}`Database.RowsWideAt`), and the stored default fits the strict type
({name}`Database.StrictDefaultFitsAt`), the effect of {name}`runStatement` satisfies
{name}`Database.TypesFit` ({name}`Effect.Satisfies`): the database of a success and that of an error
with {name}`ExecutionError.constraintFail` have it, and any other error requires nothing. It assumes
nothing about the other
atoms or the support check. Proof sketch: {name}`runStatement_addColumn_rowLocal` with
{name}`Table.TypesFit.appendColumn`. -/
theorem runStatement_addColumn_typesFit (clock : Int) (parameters : List Value) (target : Nat)
    (column : CatalogColumn) {database : Database} (fits : database.TypesFit)
    (wide : database.RowsWideAt target) (strict : database.StrictDefaultFitsAt target column) :
    (runStatement clock parameters (.addColumn target column) database).effect.Satisfies Database.TypesFit :=
  runStatement_addColumn_rowLocal clock parameters target column fits fun table _ found added =>
    (fits _ table found).appendColumn (wide table found) (strict table found) added

/-- The theorem of "checks hold" for ADD COLUMN, for every clock value, parameter list, target,
column and database: if the database satisfies {name}`Database.ChecksHold`, the rows of the table
at the target are wide ({name}`Database.RowsWideAt`), and each of its CHECK constraints reads only
columns below its width ({name}`Database.ChecksReadBelowAt`), the effect of {name}`runStatement`
satisfies {name}`Database.ChecksHold` ({name}`Effect.Satisfies`): the database of a success and that
of an error with {name}`ExecutionError.constraintFail` have it, and any other error requires
nothing. It assumes nothing about
the other atoms or the support check. Proof sketch: {name}`runStatement_addColumn_rowLocal` with
{name}`Table.ChecksHold.appendColumn`. -/
theorem runStatement_addColumn_checksHold (clock : Int) (parameters : List Value) (target : Nat)
    (column : CatalogColumn) {database : Database} (holds : database.ChecksHold)
    (wide : database.RowsWideAt target) (reads : database.ChecksReadBelowAt target) :
    (runStatement clock parameters (.addColumn target column) database).effect.Satisfies Database.ChecksHold :=
  runStatement_addColumn_rowLocal clock parameters target column holds fun table _ found added =>
    (holds _ table found).appendColumn (wide table found) (reads table found) added

end Belay.Sqlite.Model
