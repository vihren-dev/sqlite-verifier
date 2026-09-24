import SqliteVerifier.Execution

/-! Derived extension lemmas concern arbitrary initial rows, including duplicate
application values. They do not assume a fixed fixture or prove native refinement. -/

namespace SqliteVerifier

/-- Existing columns and cells remain, with only trailing NULL columns added. -/
def TableExtends (before after : Table) : Prop :=
  ∃ columns, after = before.appendColumns columns

/-- Every existing table is retained with its rows and old fields intact. -/
def DatabaseExtends (before after : Database) : Prop :=
  ∀ name table, before name = some table →
    ∃ result, after name = some result ∧ TableExtends table result

/-- Adding no columns is the identity, including all physical rowids. -/
theorem Table.appendColumns_nil (table : Table) : table.appendColumns [] = table := by
  cases table
  simp [Table.appendColumns, Row.appendNulls]

/-- Consecutive additions compose without changing earlier added or old cells. -/
theorem Table.appendColumns_append (table : Table) (first second : List Column) :
    (table.appendColumns first).appendColumns second = table.appendColumns (first ++ second) := by
  simp [Table.appendColumns, Row.appendNulls, List.map_map,
    List.append_assoc, Function.comp_def]

/-- Table preservation is available independently of the script convenience. -/
theorem TableExtends.refl (table : Table) : TableExtends table table :=
  ⟨[], table.appendColumns_nil.symm⟩

/-- Structural preservation composes; no such assumption is imposed on user Q. -/
theorem TableExtends.trans (first : TableExtends before middle)
    (second : TableExtends middle after) : TableExtends before after := by
  obtain ⟨a, rfl⟩ := first
  obtain ⟨b, rfl⟩ := second
  exact ⟨a ++ b, before.appendColumns_append a b⟩

/-- Unchanged databases satisfy preservation, including the empty database. -/
theorem DatabaseExtends.refl (database : Database) : DatabaseExtends database database :=
  fun _ table present => ⟨table, present, TableExtends.refl table⟩

/-- Each intermediate state retains the previously established observations. -/
theorem DatabaseExtends.trans (first : DatabaseExtends before middle)
    (second : DatabaseExtends middle after) : DatabaseExtends before after := by
  intro name table present
  obtain ⟨intermediate, present', growth⟩ := first name table present
  obtain ⟨result, present'', growth'⟩ := second name intermediate present'
  exact ⟨result, present'', growth.trans growth'⟩

/-- Creating an actually absent table cannot replace protected stored data. -/
theorem DatabaseExtends.create (database : Database) (name : String) (table : Table)
    (absent : database name = none) : DatabaseExtends database (database.set name table) := by
  intro other old present
  by_cases same : other = name
  · subst other
    simp [absent] at present
  · exact ⟨old, by simp [Database.set, same, present], TableExtends.refl old⟩

/-- Updating the target's schema extends its cells and leaves other tables alone. -/
theorem DatabaseExtends.add (database : Database) (name : String) (table : Table)
    (columns : List Column) (present : database name = some table) :
    DatabaseExtends database (database.set name (table.appendColumns columns)) := by
  intro other old oldPresent
  by_cases same : other = name
  · subst other
    have equal : old = table := Option.some.inj (oldPresent.symm.trans present)
    subst old
    exact ⟨table.appendColumns columns, by simp [Database.set], ⟨columns, rfl⟩⟩
  · exact ⟨old, by simp [Database.set, same, oldPresent], TableExtends.refl old⟩

/-- Both successful statements and modeled statement failures retain old data. -/
theorem step_extends (statement : Statement) (database : Database) (position : Nat) :
    DatabaseExtends database (step statement database position).database := by
  cases statement with
  | createTable name columns =>
    simp only [step]
    split
    · exact DatabaseExtends.refl database
    · cases h : database name with
      | none => exact DatabaseExtends.create database name ⟨columns, []⟩ h
      | some table => exact DatabaseExtends.refl database
  | addColumn name column =>
    simp only [step]
    split
    · exact DatabaseExtends.refl database
    · cases h : database name with
      | none => exact DatabaseExtends.refl database
      | some table =>
        simp only
        split
        · exact DatabaseExtends.refl database
        · exact DatabaseExtends.add database name table [column] h

/-- A later error retains the already committed prefix and all original data. -/
theorem runFrom_extends (script : List Statement) (database : Database) (position : Nat) :
    DatabaseExtends database (runFrom position script database).database := by
  induction script generalizing database position with
  | nil => exact DatabaseExtends.refl database
  | cons statement rest ih =>
    have first := step_extends statement database position
    cases h : step statement database position with
    | failure index reason result => simpa [runFrom, h] using first
    | success result =>
      simp only [h, Outcome.database] at first
      simpa [runFrom, h] using first.trans (ih result (position + 1))

/-- The reusable additive theorem holds for every initial database and outcome. -/
theorem run_extends (script : List Statement) (database : Database) :
    DatabaseExtends database (run script database).database :=
  runFrom_extends script database 0

/-- No row identity, multiplicity, or represented row order is lost. -/
theorem TableExtends.rowids (extension : TableExtends before after) :
    after.rows.map Row.rowid = before.rows.map Row.rowid := by
  obtain ⟨columns, rfl⟩ := extension
  simp [Table.appendColumns, Row.appendNulls, List.map_map, Function.comp_def]

/-- Reading all original stored columns yields their exact previous values. -/
theorem TableExtends.oldValues (extension : TableExtends before after)
    (width : ∀ row ∈ before.rows, row.values.length = before.columns.length) :
    after.rows.map (fun row => row.values.take before.columns.length) =
      before.rows.map Row.values := by
  obtain ⟨columns, rfl⟩ := extension
  simp only [Table.appendColumns, List.map_map]
  apply List.map_congr_left
  intro row member
  simp [Row.appendNulls, ← width row member]

end SqliteVerifier
