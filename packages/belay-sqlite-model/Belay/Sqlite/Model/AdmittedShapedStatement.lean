import Belay.Sqlite.Model.AdmittedRowsOnly
import Belay.Sqlite.Model.RowLocalAddColumn
import Belay.Sqlite.Model.RowLocalWrites
import Belay.Sqlite.Model.RowLocalSchema

set_option doc.verso true

/-! The statement theorem of the atom "rows shaped" (ADR 0022, D3, slice 4). A database is shaped when
it has one row list for each catalog object and no rows at a position without a table. CREATE appends
an object and an empty row list, ADD COLUMN and DROP change both lists together, and a write stores
the rows of a table. So the theorem needs no support check and no other atom. -/

namespace Belay.Sqlite.Model

/-- For every clock value, counters, parameter list, resolved statement and database: if the database
satisfies "rows shaped" ({name}`Database.RowsShaped`), the effect of {name}`runStatement` satisfies it
({name}`Effect.Satisfies`): the database of a success and that of an error with
{name}`ExecutionError.constraintFail` have one row list for each catalog object and no rows at a
position without a table, and any other error requires nothing. The theorem has no condition on the
connection, on the support check ({name}`StatementRun.ready`) or on other atoms, and it covers every
form of {name}`Resolved.Statement`. Proof sketch: a case for each form; CREATE appends an object and an
empty row list ({name}`Database.RowsShaped.append`), ADD COLUMN and DROP are
{name}`Database.RowsShaped.addColumn` and {name}`Database.RowsShaped.drop`, a write without rules
stores the rows of one table ({name}`runStatement_plain_rowsOnly`), a write with rules is a write of
the row engine ({name}`rowsKeys_satisfies`, {name}`dropKeys_holds` with {name}`rowsShapedLaws`), and
a statement without writes keeps the database. -/
theorem runStatement_rowsShaped (clock : Int) (counters : Counters) (parameters : List Value)
    (statement : Resolved.Statement) {database : Database} (shaped : database.RowsShaped) :
    (runStatement clock counters parameters statement database).effect.Satisfies Database.RowsShaped := by
  cases statement with
  | createTable target name table =>
    simp only [runStatement, step]
    split
    · exact Effect.satisfies_of_effectDatabase (shaped.append _)
    · exact Effect.satisfies_of_database shaped rfl
  | createIndex target name index =>
    simp only [runStatement, step]
    split
    · split
      · exact Effect.satisfies_of_database shaped rfl
      · split
        · exact Effect.satisfies_of_database shaped rfl
        · exact Effect.satisfies_of_effectDatabase (shaped.append _)
    · exact Effect.satisfies_of_database shaped rfl
  | createTrigger target name trigger =>
    simp only [runStatement, step]
    split
    · exact Effect.satisfies_of_effectDatabase (shaped.append _)
    · exact Effect.satisfies_of_database shaped rfl
  | addColumn target column =>
    simp only [runStatement]
    rcases step_addColumn_cases clock counters parameters target column database with kept | ⟨table, value, found, _, eq⟩
    · exact Effect.satisfies_of_database shaped kept
    · refine Effect.satisfies_of_effectDatabase ?_
      show (effectDatabase _).RowsShaped
      rw [eq]
      exact shaped.addColumn found column value
  | drop positions rules =>
    cases rules with
    | none =>
      simp only [runStatement, Option.map_none, StatementRun.withKeys, step]
      exact Effect.satisfies_of_effectDatabase (shaped.drop positions)
    | some rules =>
      simp only [runStatement, Option.map_some, StatementRun.withKeys]
      exact Effect.satisfies_of_effectDatabase
        (dropKeys_holds rowsShapedLaws rules clock positions shaped fun _ _ other => other.drop positions)
  | begin => exact Effect.satisfies_of_database shaped (runStatement_keeps_database clock counters parameters database _ (by simp))
  | commit => exact Effect.satisfies_of_database shaped (runStatement_keeps_database clock counters parameters database _ (by simp))
  | rollback => exact Effect.satisfies_of_database shaped (runStatement_keeps_database clock counters parameters database _ (by simp))
  | prepareError error =>
    exact Effect.satisfies_of_database shaped (runStatement_keeps_database clock counters parameters database _ (by simp))
  | query query subqueries =>
    exact Effect.satisfies_of_database shaped (runStatement_keeps_database clock counters parameters database _ (by simp))
  | setting setting on =>
    exact Effect.satisfies_of_database shaped (runStatement_keeps_database clock counters parameters database _ (by simp))
  | insert target rows returning subqueries rules =>
    cases rules with
    | none =>
      exact Effect.satisfies_of_effectDatabase
        ((runStatement_plain_rowsOnly clock counters parameters _ database target (.inl ⟨rows, returning, subqueries, rfl⟩)).shaped shaped)
    | some rules =>
      simp only [runStatement, Option.map_some, StatementRun.withKeys]
      split
      · exact Effect.satisfies_of_database shaped rfl
      · exact rowsKeys_satisfies rowsShapedLaws rules clock target _ shaped _ _
  | update target assignments filter returning subqueries rules =>
    cases rules with
    | none =>
      exact Effect.satisfies_of_effectDatabase
        ((runStatement_plain_rowsOnly clock counters parameters _ database target
          (.inr (.inl ⟨assignments, filter, returning, subqueries, rfl⟩))).shaped shaped)
    | some rules =>
      simp only [runStatement, Option.map_some, StatementRun.withKeys]
      split
      · exact Effect.satisfies_of_database shaped rfl
      · exact rowsKeys_satisfies rowsShapedLaws rules _ target _ shaped _ _
  | upsert target rows clauses returning algorithm subqueries rules =>
    cases rules with
    | none =>
      exact Effect.satisfies_of_effectDatabase
        ((runStatement_plain_rowsOnly clock counters parameters _ database target
          (.inr (.inr (.inl ⟨rows, clauses, returning, algorithm, subqueries, rfl⟩)))).shaped shaped)
    | some rules =>
      simp only [runStatement, Option.map_some, StatementRun.withKeys]
      split
      · exact Effect.satisfies_of_database shaped rfl
      · exact rowsKeys_satisfies rowsShapedLaws rules clock target _ shaped _ _
  | delete target filter returning subqueries rules =>
    cases rules with
    | none =>
      exact Effect.satisfies_of_effectDatabase
        ((runStatement_plain_rowsOnly clock counters parameters _ database target
          (.inr (.inr (.inr ⟨filter, returning, subqueries, rfl⟩)))).shaped shaped)
    | some rules =>
      simp only [runStatement, Option.map_some, StatementRun.withKeys]
      split
      · exact Effect.satisfies_of_database shaped rfl
      · exact rowsKeys_satisfies rowsShapedLaws rules _ target _ shaped _ _

end Belay.Sqlite.Model
