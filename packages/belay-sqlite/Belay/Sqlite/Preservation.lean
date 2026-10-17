import Belay.Sqlite.SqlProofs

set_option doc.verso true

/-! Derived extension lemmas concern arbitrary initial rows, including duplicate
application values. They do not assume a fixed fixture or prove native refinement. -/

namespace Belay.Sqlite

/-- There exists a list of trailing column/value pairs whose affinity-applied extension of the before
table equals the after table. This includes equality through an empty extension.
Use it to preserve old cells and physical row identities. -/
def TableExtends (before after : Table) : Prop :=
  ∃ columns, after = before.appendColumns columns

/-- For every catalog position and table present before execution, there exists a
table present after execution that satisfies {name}`TableExtends`. An empty before
database imposes no requirement. New tables are allowed. -/
def DatabaseExtends (before after : Database) : Prop :=
  ∀ position table, before position = some table →
    ∃ result, after position = some result ∧ TableExtends table result

/-- For every table, appending no columns gives the same table, including its
rows and keys. The proof unfolds the table and row operations. -/
theorem Table.appendColumns_nil (table : Table) : table.appendColumns [] = table := by
  cases table
  simp [Table.appendColumns, Row.appendValues]

/-- For every table and two column/value lists, consecutive extensions equal one
extension by their concatenation. The proof distributes row mapping over append. -/
theorem Table.appendColumns_append (table : Table) (first second : List (CatalogColumn × Value)) :
    (table.appendColumns first).appendColumns second = table.appendColumns (first ++ second) := by
  simp [Table.appendColumns, Row.appendValues, List.map_map,
    List.append_assoc, Function.comp_def]

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

/-- For every database and position without a table, setting a table at that
position extends the database. Existing tables at other positions are unchanged;
no condition is imposed on the new table. The proof separates equal and distinct
positions. -/
theorem DatabaseExtends.create (database : Database) (position : Nat) (table : Table)
    (absent : database position = none) : DatabaseExtends database (database.set position table) := by
  intro other old present
  by_cases same : other = position
  · subst other
    simp [absent] at present
  · exact ⟨old, by simp [Database.set, same, present], TableExtends.refl old⟩

/-- For every present table and any column/value list, setting its extension at
its existing position extends the database. Other tables are unchanged. The proof
uses the supplied presence equality for the selected position. -/
theorem DatabaseExtends.add (database : Database) (position : Nat) (table : Table)
    (columns : List (CatalogColumn × Value)) (present : database position = some table) :
    DatabaseExtends database (database.set position (table.appendColumns columns)) := by
  intro other old oldPresent
  by_cases same : other = position
  · subst other
    have equal : old = table := Option.some.inj (oldPresent.symm.trans present)
    subst old
    exact ⟨table.appendColumns columns, by simp [Database.set], ⟨columns, rfl⟩⟩
  · exact ⟨old, by simp [Database.set, same, oldPresent], TableExtends.refl old⟩

/-- For every statement, database and position, the primitive {name}`step`
result extends the input database. CREATE/ADD extend existing tables or retain
errors; other constructors return an unchanged error. This is a primitive schema
fact, not a preservation law for literal SQL writes. The proof follows the
primitive branches and table-update witnesses. -/
theorem step_extends (statement : Resolved.Statement) (database : Database) (position : Nat) :
    DatabaseExtends database (step statement database position).database := by
  cases statement with
  | createTable at_ name table =>
    simp only [step]
    cases h : database at_ with
    | none => exact DatabaseExtends.create database at_ { shape := table, rows := [] } h
    | some table => exact DatabaseExtends.refl database
  | addColumn at_ column =>
    simp only [step]
    cases h : database at_ with
    | none => exact DatabaseExtends.refl database
    | some table =>
      simp only []
      cases readDefaultValue column with
      | error _ => exact DatabaseExtends.refl database
      | ok value =>
        simp only []
        split
        · exact DatabaseExtends.refl database
        · exact DatabaseExtends.add database at_ table [(column, value)] h
  | createIndex _ _ _ => exact DatabaseExtends.refl database
  | query query =>
    have same : (step (.query query) database position).database = database := by
      simp only [step]
      split
      · repeat' split
        all_goals rfl
      · rfl
    rw [same]
    exact DatabaseExtends.refl database
  | begin => exact DatabaseExtends.refl database
  | commit => exact DatabaseExtends.refl database
  | rollback => exact DatabaseExtends.refl database
  | insert _ _ _ _ => exact DatabaseExtends.refl database
  | upsert _ _ _ _ _ => exact DatabaseExtends.refl database
  | update _ _ _ _ _ => exact DatabaseExtends.refl database
  | delete _ _ _ => exact DatabaseExtends.refl database
  | prepareError _ => exact DatabaseExtends.refl database

/-- For every script containing only CREATE/ADD, idle starting database and
position, the computed SQL result extends the starting database. Invalid schema
attempts and later errors retain the successful prefix. This makes no claim for
data writes or transaction control. The proof inducts over the guarded schema
transitions and composes their table preservation witnesses. -/
theorem runSqlFrom_extends (guard : SchemaOnly script) :
    DatabaseExtends database (runSqlFrom position script { database := database }).database := by
  induction script generalizing database position with
  | nil => exact DatabaseExtends.refl database
  | cons statement rest ih =>
    have head : SchemaOnly [statement] := fun item member => by
      simp only [List.mem_singleton] at member
      subst item
      exact guard statement (by simp)
    have tail : SchemaOnly rest := fun item member => guard item (by simp [member])
    have first := step_extends statement database position
    cases h : step statement database position with
    | failure index reason result => simpa [runSqlFrom, advance_schemaOnly head, h] using first
    | success result =>
      simp only [h, Outcome.database] at first
      simpa [runSqlFrom, advance_schemaOnly head, h] using first.trans (ih tail (database := result))
    | pending persisted visible error => simpa [runSqlFrom, advance_schemaOnly head, h] using first

/-- For every schema-only script and starting database, {name}`runSql` preserves
all existing tables, rows and old fields, including failure prefixes. The guard
excludes writes and transaction control. This is the idle, position-zero instance
of {name}`runSqlFrom_extends`; it does not claim native refinement. -/
theorem runSql_extends (guard : SchemaOnly script) (database : Database) :
    DatabaseExtends database (runSql script database).database :=
  runSqlFrom_extends guard

/-- For every table extension, the ordered list of after rowids equals the
before list. The proof unfolds value extension; duplicate rowids are not excluded
by this statement. -/
theorem TableExtends.rowids (extension : TableExtends before after) :
    after.rows.map Row.rowid = before.rows.map Row.rowid := by
  obtain ⟨columns, rfl⟩ := extension
  simp [Table.appendColumns, Row.appendValues, List.map_map, Function.comp_def]

/-- For every table extension whose before rows each have the before column
width, taking that many values from every after row gives the exact ordered
before value lists. With no rows the claim is vacuous. The proof unfolds value
extension and uses the width assumption for each row. -/
theorem TableExtends.oldValues (extension : TableExtends before after)
    (width : ∀ row ∈ before.rows, row.values.length = before.shape.columns.length) :
    after.rows.map (fun row => row.values.take before.shape.columns.length) =
      before.rows.map Row.values := by
  obtain ⟨columns, rfl⟩ := extension
  simp only [Table.appendColumns, List.map_map]
  apply List.map_congr_left
  intro row member
  simp [Row.appendValues, ← width row member]

end Belay.Sqlite
