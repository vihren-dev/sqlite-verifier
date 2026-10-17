import Belay.Sqlite.SqlExecution
import Belay.Sqlite.LiteralPreservation
import Belay.Sqlite.UpdatePreservation
import Belay.Sqlite.StoreValueLaws

set_option doc.verso true

/-! Preservation of {lit}`Conforms` by INSERT and UPDATE (ADR 0012, amendment 1,
"Proofs"): every row that a write produces has a valid rowid, one cell per column and
every cell in stored form. DELETE is in {lit}`DeletePreservation`. Schema statements keep {lit}`Conforms` by
{lit}`Conforms.appendAt` and {lit}`Conforms.set`. -/

namespace Belay.Sqlite

/-- For every table and value rows, every row of the table is a row of
{name}`LiteralData.inserted`: INSERT only appends. Proof sketch: induction on the value
rows; each {name}`LiteralData.insertRow` keeps the old rows before the new one. -/
theorem LiteralData.mem_inserted {table : Table} {rows : List (List Value)} {row : Row}
    (member : row ∈ table.rows) : row ∈ (inserted table rows).rows := by
  induction rows generalizing table with
  | nil => exact member
  | cons values rest ih =>
    exact ih (by simp [insertRow, member])

/-- For every table and value rows, {name}`LiteralData.inserted` keeps the shape. Proof
sketch: induction on the value rows; each {name}`LiteralData.insertRow` keeps the shape. -/
theorem LiteralData.inserted_shape (table : Table) (rows : List (List Value)) :
    (inserted table rows).shape = table.shape := by
  induction rows generalizing table with
  | nil => rfl
  | cons values rest ih => exact (ih _).trans rfl

/-- For every table and value rows: assume {name}`Table.RowsValid`,
{name}`LiteralData.aliasReady`, one value per column and {name}`LiteralData.storedForm` for
each column/value pair in every row, and a bounded rowid for every row of the inserted
table. Then {name}`LiteralData.inserted` satisfies {name}`Table.RowsValid`. Proof sketch:
induction on the rows; each new row has a rowid of the final table, so it is bounded,
and {name}`Table.RowsValid.insertRow` adds it. Distinct rowids are not claimed: an
explicit alias may repeat one, which {name}`checkedWrite` refuses. -/
theorem Table.RowsValid.inserted {table : Table} {rows : List (List Value)} (valid : table.RowsValid)
    (ready : LiteralData.aliasReady table.shape = true)
    (each : ∀ values ∈ rows, values.length = table.shape.columns.length ∧
      (table.shape.columns.zip values).all (fun (column, value) => LiteralData.storedForm column.affinity value) = true)
    (bounded : (LiteralData.inserted table rows).rows.all (fun row => LiteralData.boundedInteger row.rowid) = true) :
    (LiteralData.inserted table rows).RowsValid := by
  induction rows generalizing table with
  | nil => exact valid
  | cons values rest ih =>
    obtain ⟨width, stored⟩ := each values (by simp)
    have newMember : (⟨LiteralData.newRowid table values,
        LiteralData.newCells table values (LiteralData.newRowid table values)⟩ : Row) ∈
        (LiteralData.inserted table (values :: rest)).rows :=
      LiteralData.mem_inserted (rows := rest) (table := LiteralData.insertRow table values) (by simp [LiteralData.insertRow])
    have newBounded := List.all_eq_true.mp bounded _ newMember
    have validRow : validRowid (LiteralData.newRowid table values) := by
      simpa [LiteralData.boundedInteger, validRowid] using newBounded
    exact ih (valid.insertRow ready validRow width (Row.Stored.of_storedForm stored)) ready
      (fun values member => each values (List.mem_cons_of_mem _ member)) bounded

/-- For every profile, catalog, database, write position, result table, keys and
statement position: assume {name}`Conforms`, a table at the write position with the
result's shape, and {name}`Table.RowsValid` of the result. Then the database of
{name}`checkedWrite` conforms: it stores the result, whose rowids its check makes
distinct, or keeps the input database on a constraint failure. Proof sketch: the success
branch is {name}`Conforms.replaceRows` with the distinct rowids of the check; the failure
branch keeps the database. -/
theorem checkedWrite_conforms {old result : Table} (conforms : Conforms profile catalog database)
    (present : database at_ = some old) (shape : result.shape = old.shape) (rows : result.RowsValid)
    (keys : List (List Nat)) (position : Nat) :
    Conforms profile catalog (checkedWrite database at_ keys result position).database := by
  unfold checkedWrite
  split
  · rename_i passed
    have distinct := of_decide_eq_true ((Bool.and_eq_true _ _).mp passed).2
    exact conforms.replaceRows present shape ⟨distinct, rows⟩
  · exact conforms

/-- For every profile, catalog and database, and every INSERT that
{name}`statementReady` admits: if the database {name}`Conforms` to the catalog, so does
the database of its step, at every statement position. Proof sketch: without a table the
step fails and keeps the database; a {lit}`datatype mismatch` or a failure before it
keeps the database; otherwise {name}`LiteralData.insertReady` gives the premises of
{name}`Table.RowsValid.inserted`, and {name}`checkedWrite_conforms` applies. -/
theorem literalStep_insert_conforms (conforms : Conforms profile catalog database)
    (ready : statementReady (.insert at_ rows keys returning) database = true) (position : Nat) :
    Conforms profile catalog (literalStep (.insert at_ rows keys returning) database position).database := by
  cases present : database at_ with
  | none => simp only [literalStep, present]; exact conforms
  | some table =>
    simp only [literalStep, present, insertOutcome]
    simp only [statementReady, present, Option.all_some, LiteralData.insertReady, Bool.and_eq_true] at ready
    obtain ⟨⟨⟨⟨_, aliasOk⟩, each⟩, bounded⟩, _⟩ := ready
    have valid := (conforms.2 at_).2 table present
    split
    · split <;> exact conforms
    · refine checkedWrite_conforms conforms present (LiteralData.inserted_shape table rows)
        (valid.2.inserted aliasOk ?_ bounded) _ _
      intro values member
      have check := List.all_eq_true.mp each values member
      simp only [Bool.and_eq_true, beq_iff_eq] at check
      exact ⟨check.1, check.2⟩

/-- For every profile, catalog and database, and every UPDATE that {name}`statementReady`
admits: if the database {name}`Conforms` to the catalog, so does the database of its
step, at every statement position. Proof sketch: without a table, or with a
{lit}`datatype mismatch`, the step keeps the database; otherwise
{name}`LiteralData.updateReady` gives the premises of {name}`Table.RowsValid.updated`, and
{name}`checkedWrite_conforms` applies. -/
theorem literalStep_update_conforms (conforms : Conforms profile catalog database)
    (ready : statementReady (.update at_ assignments filter keys returning) database = true) (position : Nat) :
    Conforms profile catalog (literalStep (.update at_ assignments filter keys returning) database position).database := by
  cases present : database at_ with
  | none => simp only [literalStep, present]; exact conforms
  | some table =>
    simp only [literalStep, present]
    simp only [statementReady, present, Option.all_some, LiteralData.updateReady, Bool.and_eq_true] at ready
    obtain ⟨⟨⟨⟨_, aliasOk⟩, _⟩, bounded⟩, _⟩ := ready
    split
    · exact conforms
    · rename_i fits
      exact checkedWrite_conforms conforms present (result := LiteralData.updated table assignments filter) rfl
        (Table.RowsValid.updated ((conforms.2 at_).2 table present) assignments filter
          (by simpa using fits) bounded) _ _

end Belay.Sqlite
