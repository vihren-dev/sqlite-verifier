import Belay.Sqlite.Model.SqlLaws
import Belay.Sqlite.Model.DatabaseWriteLaws

set_option doc.verso true

/-! Derived extension lemmas concern arbitrary initial rows, including duplicate
application values. They do not assume a fixed fixture or prove native refinement. -/

namespace Belay.Sqlite.Model

/-- There exists a list of trailing column/value pairs whose affinity-applied extension of the before
table equals the after table. This includes equality through an empty extension.
Use it to preserve old cells and physical row identities. -/
def TableExtends (before after : Table) : Prop :=
  ∃ columns, after = before.appendColumns columns

/-- For every catalog position and table present before execution, there exists a
table present after execution that satisfies {name}`TableExtends`. An empty before
database imposes no requirement. New tables are allowed. -/
def DatabaseExtends (before after : Database) : Prop :=
  ∀ position table, before.table position = some table →
    ∃ result, after.table position = some result ∧ TableExtends table result

/-- Every table extends itself, witnessed by an empty list of appended columns. -/
theorem TableExtends.refl (table : Table) : TableExtends table table :=
  ⟨[], table.appendColumns_nil.symm⟩

/-- Whenever a before table extends to a middle table and that middle table
extends to an after table, the before table extends to the after table. The proof
concatenates the extension lists; it assumes nothing about application contracts. -/
theorem TableExtends.trans (first : TableExtends before middle)
    (second : TableExtends middle after) : TableExtends before after := by
  obtain ⟨a, rfl⟩ := first
  obtain ⟨b, rfl⟩ := second
  exact ⟨a ++ b, before.appendColumns_append a b⟩

/-- Every database extends itself: each present table is retained unchanged.
This includes an empty database, where the table premise is always false. -/
theorem DatabaseExtends.refl (database : Database) : DatabaseExtends database database :=
  fun _ table present => ⟨table, present, TableExtends.refl table⟩

/-- If a before database extends to a middle database and the middle extends to
an after database, the before extends to the after. The proof retrieves each
present intermediate table and composes its table extension witnesses. -/
theorem DatabaseExtends.trans (first : DatabaseExtends before middle)
    (second : DatabaseExtends middle after) : DatabaseExtends before after := by
  intro position table present
  obtain ⟨intermediate, present', growth⟩ := first position table present
  obtain ⟨result, present'', growth'⟩ := second position intermediate present'
  exact ⟨result, present'', growth.trans growth'⟩

/-- For every database, name and catalog table, CREATE TABLE ({name}`Catalog.createTable`
with an empty row list appended) extends the database: every table present before is
present and unchanged. No condition is imposed on the new table. -/
theorem DatabaseExtends.create (database : Database) (name : Identifier) (table : CatalogTable) :
    DatabaseExtends database
      { catalog := database.catalog.createTable name table, rows := database.rows ++ [[]] } :=
  fun _ old present => ⟨old, Database.table_createTable name table present, TableExtends.refl old⟩

/-- For every database and object, appending the object to the catalog and an empty row list
extends the database, as CREATE INDEX and CREATE TRIGGER do: every table keeps its position and
is unchanged. Proof sketch: {name}`Database.table_append` keeps each present table at its
position, and {name}`TableExtends.refl` extends it by no columns. -/
theorem DatabaseExtends.append (database : Database) (object : CatalogObject) :
    DatabaseExtends database { catalog := database.catalog ++ [object], rows := database.rows ++ [[]] } :=
  fun _ old present => ⟨old, Database.table_append object present, TableExtends.refl old⟩

/-- For every present table, column and value, {name}`Database.addColumn` at its position
extends the database. Other tables are unchanged. The proof separates the selected
position from the others. -/
theorem DatabaseExtends.add (database : Database) (position : Nat) (table : Table) (column : CatalogColumn)
    (value : Value) (present : database.table position = some table) :
    DatabaseExtends database (database.addColumn position column value) := by
  intro other old oldPresent
  by_cases same : other = position
  · subst other
    have equal : old = table := Option.some.inj (oldPresent.symm.trans present)
    subst old
    exact ⟨table.appendColumns [(column, value)], Database.table_addColumn column value present, ⟨_, rfl⟩⟩
  · exact ⟨old, (Database.table_addColumn_other database column value same).trans oldPresent,
      TableExtends.refl old⟩

/-- For every clock value, counters, list of values, database and statement that is not DROP (its
{name}`Resolved.Statement.kind` is not {name}`Resolved.Statement.Kind.drop`), the database of
the primitive {name}`step` effect ({name}`effectDatabase`) extends the input database. A DROP
removes tables, so the theorem says nothing about it. CREATE/ADD extend existing tables or retain
errors; other constructors return an unchanged error. This is a primitive schema
fact, not a preservation law for literal SQL writes. The proof follows the
primitive branches and table-update witnesses. -/
theorem step_extends (clock : Int) (counters : Counters) (parameters : List Value) (statement : Resolved.Statement) (database : Database)
    (kept : statement.kind ≠ .drop) :
    DatabaseExtends database (effectDatabase (step clock counters parameters statement database)) := by
  cases statement with
  | drop _ _ => exact absurd rfl kept
  | createTable target name table =>
    simp only [step]
    split
    · exact DatabaseExtends.create database name table
    · exact DatabaseExtends.refl database
  | addColumn target column =>
    simp only [step]
    cases h : database.table target with
    | none => exact DatabaseExtends.refl database
    | some table =>
      simp only []
      split
      · split
        · exact DatabaseExtends.add database target table column .null h
        · exact DatabaseExtends.refl database
      · cases readDefaultValue column with
        | error _ => exact DatabaseExtends.refl database
        | ok value =>
          simp only []
          split
          · exact DatabaseExtends.refl database
          · split
            · exact DatabaseExtends.refl database
            · exact DatabaseExtends.add database target table column value h
  | createIndex target name index =>
    simp only [step]
    split
    · split
      · exact DatabaseExtends.refl database
      · split
        · exact DatabaseExtends.refl database
        · exact DatabaseExtends.append database _
    · exact DatabaseExtends.refl database
  | createTrigger target name trigger =>
    simp only [step]
    split
    · exact DatabaseExtends.append database _
    · exact DatabaseExtends.refl database
  | query query subqueries =>
    have same : effectDatabase (step clock counters parameters (.query query subqueries) database) = database := by
      simp only [step, queryEffect]
      repeat' split
      all_goals rfl
    rw [same]
    exact DatabaseExtends.refl database
  | begin => exact DatabaseExtends.refl database
  | commit => exact DatabaseExtends.refl database
  | rollback => exact DatabaseExtends.refl database
  | insert => exact DatabaseExtends.refl database
  | upsert => exact DatabaseExtends.refl database
  | update => exact DatabaseExtends.refl database
  | delete => exact DatabaseExtends.refl database
  | prepareError _ => exact DatabaseExtends.refl database
  | setting _ => exact DatabaseExtends.refl database

/-- For every script of statements with any values whose statements are only CREATE/ADD,
idle starting database and position, the computed SQL result extends the starting database. Invalid schema
attempts and later errors retain the successful prefix. This makes no claim for
data writes or transaction control. The proof inducts over the guarded schema
transitions and composes their table preservation witnesses. -/
theorem runSqlFrom_extends (guard : SchemaOnly (script.map (·.1))) :
    DatabaseExtends database (runSqlFrom position script { database := database }).database := by
  induction script generalizing database position with
  | nil => exact DatabaseExtends.refl database
  | cons entry rest ih =>
    obtain ⟨statement, parameters⟩ := entry
    have head : SchemaOnly [statement] := fun item member => by
      simp only [List.mem_singleton] at member
      subst item
      exact guard statement (by simp)
    have tail : SchemaOnly (rest.map (·.1)) := fun item member => guard item (by simp_all)
    have first := step_extends 0 {} parameters statement database (by rw [guard statement (by simp)]; decide)
    cases h : step 0 {} parameters statement database with
    | error failure => simpa [runSqlFrom, advance_schemaOnly head, h, Outcome.database] using DatabaseExtends.refl database
    | ok result =>
      simp only [h, effectDatabase] at first
      simpa [runSqlFrom, advance_schemaOnly head, h] using first.trans (ih tail (database := result))

/-- For every script of statements with any values whose statements are schema-only, and every
starting database, {name}`runSql` preserves
all existing tables, rows and old fields, including failure prefixes. The guard
excludes writes and transaction control. This is the idle, position-zero instance
of {name}`runSqlFrom_extends`; it does not claim native refinement. -/
theorem runSql_extends (guard : SchemaOnly (script.map (·.1))) (database : Database) :
    DatabaseExtends database (runSql script database).database :=
  runSqlFrom_extends guard

end Belay.Sqlite.Model
