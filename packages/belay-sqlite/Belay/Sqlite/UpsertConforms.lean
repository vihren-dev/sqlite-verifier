import Belay.Sqlite.UpsertPreservation

set_option doc.verso true

/-! {lit}`Conforms` after INSERT with {lit}`ON CONFLICT` clauses or conflict algorithms
(ADR 0012, amendment 4, slices 5c and 5d): by induction on the rows, each row of
{lit}`LiteralData.upsertRun` keeps the table's shape and {lit}`Table.Valid`, so the final
table conforms, and so does the table before a failing row, which a FAIL failure keeps. -/

namespace Belay.Sqlite

/-- For every valid table and one row: assume {name}`LiteralData.aliasReady`, one value
per column in stored form, a bounded {name}`LiteralData.newRowid`, and bounded rowids in
the table after the row. If {name}`LiteralData.upsertRow` succeeds, its table has the
same shape and is {name}`Table.Valid`. Proof sketch: the proposed row has the conditions
of the row that {name}`Table.RowsValid.insertRow` appends; a skipped row keeps the table;
an inserted row is {name}`LiteralData.insertChecked_valid`; an updated row is
{name}`LiteralData.updateExisting_valid` of a row of the table
({name}`LiteralData.handlingClause_mem`). -/
theorem LiteralData.upsertRow_valid {keys : List (List Nat)} {policy : Resolved.ConflictPolicy}
    {clauses : List Resolved.ConflictClause} {table next : Table} {values : List Value} {written : Option Row}
    (valid : table.Valid) (ready : aliasReady table.shape = true) (width : values.length = table.shape.columns.length)
    (stored : Row.Stored table.shape.columns { rowid := 0, values })
    (boundedNew : boundedInteger (newRowid table values) = true)
    (bounded : next.rows.all (fun row => boundedInteger row.rowid) = true)
    (step : upsertRow keys policy clauses table values = .ok (next, written)) :
    next.shape = table.shape ∧ next.Valid := by
  have proposed := valid.2.insertRow ready (by simpa [boundedInteger, validRowid] using boundedNew) width stored
    (proposedRow table values) (by simp [insertRow, proposedRow])
  unfold upsertRow at step
  dsimp only at step
  split at step
  · cases step
  split at step
  · obtain rfl := failedConstraint_ok step
    exact ⟨rfl, valid⟩
  split at step
  · exact insertChecked_valid valid proposed step
  · rename_i clause existing found
    have member := handlingClause_mem found
    split at step
    · cases step; exact ⟨rfl, valid⟩
    · exact updateExisting_valid valid member bounded step

/-- The table of the result of a run: the final table, or the table before the failing
row. -/
def LiteralData.runTable : Except (ExecutionError × Table × List Row) (Table × List Row) → Table
  | .ok (final, _) => final
  | .error (_, reached, _) => reached

/-- For every valid table and value rows: assume {name}`LiteralData.aliasReady`, one
value per column in stored form in every row, and {name}`LiteralData.upsertBounded`.
Then the table of the run ({name}`LiteralData.runTable`), the final table or the table
before the failing row, has the same shape and is {name}`Table.Valid`. Proof sketch:
induction on the rows with {name}`LiteralData.upsertRow_valid`; each row keeps the shape,
so the premises about the shape hold for the next row. -/
theorem LiteralData.upsertRun_valid {keys : List (List Nat)} {policy : Resolved.ConflictPolicy}
    {clauses : List Resolved.ConflictClause} :
    ∀ {rows : List (List Value)} {table : Table}, table.Valid → aliasReady table.shape = true →
    (∀ values ∈ rows, values.length = table.shape.columns.length ∧
      (table.shape.columns.zip values).all (fun (column, value) => storedForm column.affinity value) = true) →
    upsertBounded keys policy clauses table rows = true →
    (runTable (upsertRun keys policy clauses table rows)).shape = table.shape ∧
      (runTable (upsertRun keys policy clauses table rows)).Valid
  | [], _, valid, _, _, _ => ⟨rfl, valid⟩
  | values :: rest, table, valid, ready, each, bounded => by
    simp only [upsertBounded, Bool.and_eq_true] at bounded
    obtain ⟨boundedNew, boundedRest⟩ := bounded
    unfold upsertRun
    split
    · exact ⟨rfl, valid⟩
    rename_i next written step
    rw [step] at boundedRest
    simp only [Bool.and_eq_true] at boundedRest
    obtain ⟨width, storedForm⟩ := each values (by simp)
    obtain ⟨shape, nextValid⟩ := upsertRow_valid valid ready width (Row.Stored.of_storedForm storedForm)
      boundedNew boundedRest.1 step
    obtain ⟨restShape, restValid⟩ := upsertRun_valid (rows := rest) nextValid (shape ▸ ready)
      (fun row member => shape ▸ each row (List.mem_cons_of_mem _ member)) boundedRest.2
    split <;> rename_i result <;> simp only [runTable] at restShape restValid ⊢ <;> rw [result] at restShape restValid
      <;> exact ⟨restShape.trans shape, restValid⟩

/-- For every profile, catalog and database, and every UPSERT that
{name}`statementReady` admits: if the database {name}`Conforms` to the catalog, so does
the database of its step, at every statement position. Proof sketch: without a table the
step keeps the database; otherwise {name}`LiteralData.upsertRun_valid` gives the shape
and validity of the final table and of the table before a failing row, and
{name}`Conforms.replaceRows` stores the one that the step keeps. -/
theorem literalStep_upsert_conforms (conforms : Conforms profile catalog database)
    (ready : statementReady (.upsert at_ rows clauses keys returning policy) database = true) (position : Nat) :
    Conforms profile catalog (literalStep (.upsert at_ rows clauses keys returning policy) database position).database := by
  cases present : database at_ with
  | none => simp only [literalStep, present]; exact conforms
  | some table =>
    simp only [literalStep, present]
    simp only [statementReady, present, Option.all_some, LiteralData.upsertReady, Bool.and_eq_true] at ready
    obtain ⟨⟨⟨⟨_, aliasOk⟩, each⟩, _⟩, bounded⟩ := ready
    have run := LiteralData.upsertRun_valid ((conforms.2 at_).2 table present) aliasOk
      (fun values member => by
        have check := List.all_eq_true.mp each values member
        simp only [Bool.and_eq_true, beq_iff_eq] at check
        exact ⟨check.1, check.2⟩) bounded (keys := keys) (policy := policy) (clauses := clauses)
    split
    · rename_i result _ found
      rw [found] at run
      exact conforms.replaceRows present run.1 run.2
    · rename_i reason reached _ found
      rw [found] at run
      cases reason <;> simp only [LiteralData.failedDatabase]
      all_goals first | exact conforms | exact conforms.replaceRows present run.1 run.2

end Belay.Sqlite
