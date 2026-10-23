import Belay.Sqlite.Model.RowLocalFrame
import Belay.Sqlite.Model.KeysUniqueWrites
import Belay.Sqlite.Model.StatementStep

set_option doc.verso true

/-! The theorems of the atoms "not null", "types fit" and "checks hold" (ADR 0022, D3, slice 3),
stated for every {lit}`RowLocalAtom`, for plain INSERT, UPDATE and DELETE, the writes without the
row engine (no foreign keys checked and no trigger programs), and for the statements that write no
row: a query, a setting, a prepare error, BEGIN, COMMIT and ROLLBACK. {lit}`RowLocalWriteTheorems`
states them for each atom. -/

namespace Belay.Sqlite.Model

/-- For every table and rows, {name}`LiteralData.inserted` keeps the catalog entry of the table.
Proof sketch: induction on the rows; {name}`LiteralData.insertRow` changes only the rows. -/
theorem LiteralData.inserted_shape (table : Table) (rows : List (List Value)) :
    (LiteralData.inserted table rows).shape = table.shape := by
  unfold LiteralData.inserted
  induction rows generalizing table with
  | nil => rfl
  | cons values rest ih => exact (ih _).trans rfl

/-- For every atom, database, position, table, keys and result table: if the atom is a
{name}`RowLocalAtom`, every table of the database has it, the database has the table at the
position, and the result has the catalog entry of the table, the effect of
{name}`checkedWrite` satisfies "every table has the atom" ({name}`Effect.Satisfies`): the database
of a success and that of an error with {name}`ExecutionError.constraintFail` have it, and any other
error requires nothing. Proof sketch: a stored result passed {name}`LiteralData.constraints`, so
the atom holds for it ({name}`RowLocalAtom.constraints`), and {name}`Database.EachTable.setRows`
stores its rows; a failure keeps the database. -/
theorem checkedWrite_rowLocal {atom : Table → Prop} (rowLocal : RowLocalAtom atom) {database : Database}
    (every : database.EachTable atom) {target : Nat} {table : Table} (found : database.table target = some table)
    (keys : List UniqueKey) (result : Table) (shape : result.shape = table.shape) :
    (checkedWrite database target keys result).Satisfies fun after => after.EachTable atom := by
  unfold checkedWrite
  split
  · rename_i passed
    simp only [Bool.and_eq_true] at passed
    have whole : ({ table with rows := result.rows } : Table) = result := by cases result; simp_all
    exact Effect.satisfies_of_effectDatabase (every.setRows found (whole ▸ rowLocal.constraints keys result passed.1))
  · exact Effect.satisfies_of_database every rfl

/-- For every atom, database, position, table, keys, rows and result table: if the atom is a
{name}`RowLocalAtom`, every table of the database has it, the database has the table at the
position, and the result has the catalog entry of the table, the effect of
{name}`insertOutcome` satisfies "every table has the atom" ({name}`Effect.Satisfies`): the database
of a success and that of an error with {name}`ExecutionError.constraintFail` have it, and any other
error requires nothing. Proof sketch: a refused rowid alias fails with the input database, and
every other case is {name}`checkedWrite_rowLocal`. -/
theorem insertOutcome_rowLocal {atom : Table → Prop} (rowLocal : RowLocalAtom atom) {database : Database}
    (every : database.EachTable atom) {target : Nat} {table : Table} (found : database.table target = some table)
    (keys : List UniqueKey) (rows : List (List Value)) (result : Table) (shape : result.shape = table.shape) :
    (insertOutcome database target keys table rows result).Satisfies fun after => after.EachTable atom := by
  unfold insertOutcome
  split
  · dsimp only
    split <;> exact Effect.satisfies_of_database every rfl
  · exact checkedWrite_rowLocal rowLocal every found keys result shape

/-- For every atom, clock value, parameter list, plain INSERT (no foreign key rules and no trigger
programs: {lean}`(none : Option Resolved.WriteRules)`) and database: if the atom is a
{name}`RowLocalAtom` and every table of the database has it, the effect of {name}`runStatement`
satisfies "every table has the atom" ({name}`Effect.Satisfies`): the database of a success and that
of an error with {name}`ExecutionError.constraintFail` have it, and any other error requires
nothing. It assumes nothing about the support check. Proof sketch: a
missing table fails with the input database, and otherwise the effect is
{name}`insertOutcome_rowLocal` with {name}`LiteralData.inserted_shape`. -/
theorem runStatement_insert_rowLocal {atom : Table → Prop} (rowLocal : RowLocalAtom atom) (clock : Int)
    (parameters : List Value) (target : Nat) (rows : List (List Resolved.Cell))
    (returning : List (Resolved.Expr × String)) (subqueries : List Resolved.Query) {database : Database}
    (every : database.EachTable atom) :
    (runStatement clock parameters (.insert target rows returning subqueries none) database).effect.Satisfies
      fun after => after.EachTable atom := by
  simp only [runStatement, Option.map_none, StatementRun.withKeys]
  split
  · exact Effect.satisfies_of_database every rfl
  · rename_i table found
    exact insertOutcome_rowLocal rowLocal every found _ _ _ (LiteralData.inserted_shape _ _)

/-- For every atom, clock value, parameter list, plain UPDATE (no foreign key rules and no trigger
programs) and database: if the atom is a {name}`RowLocalAtom` and every table of the database has
it, the effect of {name}`runStatement` satisfies "every table has the atom"
({name}`Effect.Satisfies`): the database of a success and that of an error with
{name}`ExecutionError.constraintFail` have it, and any other error requires nothing. It assumes
nothing
about the support check. Proof sketch: a missing table and a refused rowid alias fail with the
input database, and otherwise the effect is {name}`checkedWrite_rowLocal`; UPDATE keeps the
catalog entry. -/
theorem runStatement_update_rowLocal {atom : Table → Prop} (rowLocal : RowLocalAtom atom) (clock : Int)
    (parameters : List Value) (target : Nat) (assignments : List (Nat × Resolved.Expr))
    (filter : Option Resolved.Expr) (returning : List (Resolved.Expr × String)) (subqueries : List Resolved.Query)
    {database : Database} (every : database.EachTable atom) :
    (runStatement clock parameters (.update target assignments filter returning subqueries none) database).effect.Satisfies
      fun after => after.EachTable atom := by
  simp only [runStatement, Option.map_none, StatementRun.withKeys]
  split
  · exact Effect.satisfies_of_database every rfl
  · rename_i table found
    split
    · exact Effect.satisfies_of_database every rfl
    · exact checkedWrite_rowLocal rowLocal every found _ _ rfl

/-- For every atom, clock value, parameter list, plain DELETE (no foreign key rules and no trigger
programs) and database: if the atom is a {name}`RowLocalAtom` and every table of the database has
it, the effect of {name}`runStatement` satisfies "every table has the atom"
({name}`Effect.Satisfies`): the database of a success and that of an error with
{name}`ExecutionError.constraintFail` have it, and any other error requires nothing. It assumes
nothing
about the support check. Proof sketch: DELETE stores a filter of the rows
({name}`LiteralData.deleted`), a sublist of the rows with the same entry ({name}`RowLocalAtom.sublist`). -/
theorem runStatement_delete_rowLocal {atom : Table → Prop} (rowLocal : RowLocalAtom atom) (clock : Int)
    (parameters : List Value) (target : Nat) (filter : Option Resolved.Expr)
    (returning : List (Resolved.Expr × String)) (subqueries : List Resolved.Query) {database : Database}
    (every : database.EachTable atom) :
    (runStatement clock parameters (.delete target filter returning subqueries none) database).effect.Satisfies
      fun after => after.EachTable atom := by
  simp only [runStatement, Option.map_none, StatementRun.withKeys]
  split
  · exact Effect.satisfies_of_database every rfl
  · rename_i table found
    refine Effect.satisfies_of_effectDatabase (every.setRows found ?_)
    exact rowLocal.sublist table _ (every _ table found) rfl (List.filter_sublist (l := table.rows))

/-- For every atom, clock value, parameter list, database and statement that writes no row (a
query, a setting, a prepare error, BEGIN, COMMIT or ROLLBACK): if every table of the database has
the atom, the effect of {name}`runStatement` satisfies "every table has the atom"
({name}`Effect.Satisfies`): the database of a success and that of an error with
{name}`ExecutionError.constraintFail` have it, and any other error requires nothing. Proof sketch:
{name}`runStatement_keeps_database`. -/
theorem runStatement_writesNone_rowLocal {atom : Table → Prop} (clock : Int) (parameters : List Value)
    {database : Database} (every : database.EachTable atom) (statement : Resolved.Statement)
    (writesNone : (∃ query subqueries, statement = .query query subqueries) ∨ (∃ setting on, statement = .setting setting on) ∨
      (∃ error, statement = .prepareError error) ∨ statement = .begin ∨ statement = .commit ∨ statement = .rollback) :
    (runStatement clock parameters statement database).effect.Satisfies fun after => after.EachTable atom :=
  Effect.satisfies_of_database every (runStatement_keeps_database clock parameters database statement writesNone)

end Belay.Sqlite.Model
