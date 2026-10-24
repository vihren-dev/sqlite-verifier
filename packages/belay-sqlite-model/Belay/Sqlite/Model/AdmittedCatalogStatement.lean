import Belay.Sqlite.Model.AdmittedRowsOnly
import Belay.Sqlite.Model.Resolution.StatementCatalog
import Belay.Sqlite.Model.RowLocalAddColumn
import Belay.Sqlite.Model.RowLocalWrites
import Belay.Sqlite.Model.RowLocalSchema

set_option doc.verso true

/-! The statement theorem of the atom "catalog supported" (ADR 0022, D3, slice 4). Only the schema
statements change the catalog, and each of them changes it as {lit}`Resolved.Statement.applyCatalog`
says, so the catalog after a run is the catalog before or the one that this function gives. The row
engine and the plain writes keep the catalog. The theorem asks for a valid catalog after the schema
statement: the resolver facts of part 3 give it for the statements that the resolver makes. -/

namespace Belay.Sqlite.Model

/-- For every limits, clock value, counters, parameter list, resolved statement and database: if the
catalog of the database is valid under the limits ({name}`Catalog.Valid`), and the catalog that
{name}`Resolved.Statement.applyCatalog` gives for the statement is valid under the limits, the effect
of {name}`runStatement` satisfies "the catalog is valid under the limits" ({name}`Effect.Satisfies`):
the database of a success and that of an error with {name}`ExecutionError.constraintFail` have a valid
catalog, and any other error requires nothing. For a statement that is not CREATE, ADD COLUMN or DROP,
the second condition is the first. The theorem has no condition on the support check
({name}`StatementRun.ready`) or on other atoms, and it covers every form of {name}`Resolved.Statement`.
Proof sketch: a run keeps the catalog, or CREATE, ADD COLUMN and DROP give the catalog of
{lit}`applyCatalog`; the plain writes keep the catalog ({name}`Database.RowsOnlyAt.catalog`), and the
row engine keeps it ({name}`rowsKeys_satisfies`, {name}`dropKeys_holds` with {name}`catalogSupportedLaws`). -/
theorem runStatement_catalogSupported (limits : Limits) (clock : Int) (counters : Counters)
    (parameters : List Value) (statement : Resolved.Statement) {database : Database}
    (valid : database.catalog.Valid limits) (next : (statement.applyCatalog database.catalog).Valid limits) :
    (runStatement clock counters parameters statement database).effect.Satisfies
      fun after => after.catalog.Valid limits := by
  cases statement with
  | createTable target name table =>
    simp only [runStatement, step]
    split
    · exact Effect.satisfies_of_effectDatabase next
    · exact Effect.satisfies_of_database valid rfl
  | createIndex target name index =>
    simp only [runStatement, step]
    split
    · split
      · exact Effect.satisfies_of_database valid rfl
      · split
        · exact Effect.satisfies_of_database valid rfl
        · exact Effect.satisfies_of_effectDatabase next
    · exact Effect.satisfies_of_database valid rfl
  | createTrigger target name trigger =>
    simp only [runStatement, step]
    split
    · exact Effect.satisfies_of_effectDatabase next
    · exact Effect.satisfies_of_database valid rfl
  | addColumn target column =>
    simp only [runStatement]
    rcases step_addColumn_cases clock counters parameters target column database with kept | ⟨table, value, found, _, eq⟩
    · exact Effect.satisfies_of_database valid kept
    · refine Effect.satisfies_of_effectDatabase ?_
      show (effectDatabase _).catalog.Valid limits
      rw [eq]
      exact next
  | drop positions rules =>
    cases rules with
    | none =>
      simp only [runStatement, Option.map_none, StatementRun.withKeys, step]
      exact Effect.satisfies_of_effectDatabase next
    | some rules =>
      simp only [runStatement, Option.map_some, StatementRun.withKeys]
      refine Effect.satisfies_of_effectDatabase
        (dropKeys_holds (catalogSupportedLaws limits) rules clock positions valid fun other same _ => ?_)
      show (other.catalog.drop positions).Valid limits
      rw [same]
      exact next
  | begin => exact Effect.satisfies_of_database valid (runStatement_keeps_database clock counters parameters database _ (by simp))
  | commit => exact Effect.satisfies_of_database valid (runStatement_keeps_database clock counters parameters database _ (by simp))
  | rollback => exact Effect.satisfies_of_database valid (runStatement_keeps_database clock counters parameters database _ (by simp))
  | prepareError error =>
    exact Effect.satisfies_of_database valid (runStatement_keeps_database clock counters parameters database _ (by simp))
  | query query subqueries =>
    exact Effect.satisfies_of_database valid (runStatement_keeps_database clock counters parameters database _ (by simp))
  | setting setting on =>
    exact Effect.satisfies_of_database valid (runStatement_keeps_database clock counters parameters database _ (by simp))
  | insert target rows returning subqueries rules =>
    cases rules with
    | none =>
      exact Effect.satisfies_of_effectDatabase
        (((runStatement_plain_rowsOnly clock counters parameters _ database target
          (.inl ⟨rows, returning, subqueries, rfl⟩)).catalog).symm ▸ valid)
    | some rules =>
      simp only [runStatement, Option.map_some, StatementRun.withKeys]
      split
      · exact Effect.satisfies_of_database valid rfl
      · exact rowsKeys_satisfies (catalogSupportedLaws limits) rules clock target _ valid _ _
  | update target assignments filter returning subqueries rules =>
    cases rules with
    | none =>
      exact Effect.satisfies_of_effectDatabase
        (((runStatement_plain_rowsOnly clock counters parameters _ database target
          (.inr (.inl ⟨assignments, filter, returning, subqueries, rfl⟩))).catalog).symm ▸ valid)
    | some rules =>
      simp only [runStatement, Option.map_some, StatementRun.withKeys]
      split
      · exact Effect.satisfies_of_database valid rfl
      · exact rowsKeys_satisfies (catalogSupportedLaws limits) rules _ target _ valid _ _
  | upsert target rows clauses returning algorithm subqueries rules =>
    cases rules with
    | none =>
      exact Effect.satisfies_of_effectDatabase
        (((runStatement_plain_rowsOnly clock counters parameters _ database target
          (.inr (.inr (.inl ⟨rows, clauses, returning, algorithm, subqueries, rfl⟩)))).catalog).symm ▸ valid)
    | some rules =>
      simp only [runStatement, Option.map_some, StatementRun.withKeys]
      split
      · exact Effect.satisfies_of_database valid rfl
      · exact rowsKeys_satisfies (catalogSupportedLaws limits) rules clock target _ valid _ _
  | delete target filter returning subqueries rules =>
    cases rules with
    | none =>
      exact Effect.satisfies_of_effectDatabase
        (((runStatement_plain_rowsOnly clock counters parameters _ database target
          (.inr (.inr (.inr ⟨filter, returning, subqueries, rfl⟩)))).catalog).symm ▸ valid)
    | some rules =>
      simp only [runStatement, Option.map_some, StatementRun.withKeys]
      split
      · exact Effect.satisfies_of_database valid rfl
      · exact rowsKeys_satisfies (catalogSupportedLaws limits) rules _ target _ valid _ _

end Belay.Sqlite.Model
