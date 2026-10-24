import Belay.Sqlite.Model.AdmittedEngineLaws

set_option doc.verso true

/-! The row engine keeps the four row atoms of {lit}`Database.Admitted` (ADR 0022, D3, slice 4, owner
decision M of the status file, finding 16): "rowids in range", "rows wide", "rows stored" and "rows
aliased". The engine stores a table whose rows are rows that were there or rows that
{lit}`LiteralData.rowAdmitted` accepts, and a row that fails the test is not stored, so each atom has the laws
of {lit}`WriteLaws` and {lit}`rowsKeys_holds` and {lit}`dropKeys_holds` apply, for every constructor of a
statement, also with rules. -/

namespace Belay.Sqlite.Model

/-- For every {name}`TableAtom` that a table with fresh rows keeps, the atom "every table has it" has the
laws of {name}`WriteLaws`. The hypothesis {lit}`fresh` says: for every table with the atom and rows, each of
which is a row of the table or is admitted for its entry ({name}`LiteralData.rowAdmitted`), the table with
the rows has the atom. Proof sketch: a DELETE stores a sublist, which the atom keeps
({name}`Database.Every.change` with the frame fact); a write stores a table with fresh rows, which
{lit}`fresh` gives ({name}`Database.Every.setRows`). -/
theorem rowAtomLaws {atom : Table → Prop} (frame : TableAtom atom)
    (fresh : ∀ (table : Table) (rows : List Row), atom table →
      (∀ row ∈ rows, row ∈ table.rows ∨ LiteralData.rowAdmitted table.shape row = true) →
      atom { table with rows }) :
    WriteLaws fun database => database.EachTable atom where
  sublist database position change every sub :=
    Database.Every.change (fact := fun _ _ table => atom table) every fun table found =>
      frame.sublist table _ (every position table found) rfl (by rw [Database.table_rows_eq found]; exact sub _)
  write database position table rows every found _ admitted :=
    Database.Every.setRows (fact := fun _ _ table => atom table) every found
      (fresh table rows (every position table found) admitted)

/-- "Rowids in range" has the laws of {name}`WriteLaws`. Proof sketch: {name}`rowAtomLaws`; a fresh row
is a row of the table, or is admitted, and an admitted row has a valid rowid
({name}`LiteralData.rowAdmitted_iff`). -/
theorem rowidsInRangeLaws : WriteLaws Database.RowidsInRange :=
  rowAtomLaws Table.rowidsInRangeAtom fun _ _ inRange fresh row member =>
    (fresh row member).elim (inRange row) fun admitted => ((LiteralData.rowAdmitted_iff _ _).mp admitted).1

/-- "Rows wide" has the laws of {name}`WriteLaws`. Proof sketch: {name}`rowAtomLaws`; an admitted row has
one cell for each column ({name}`LiteralData.rowAdmitted_iff`). -/
theorem rowsWideLaws : WriteLaws Database.RowsWide :=
  rowAtomLaws Table.rowsWideAtom fun _ _ wide fresh row member =>
    (fresh row member).elim (wide row) fun admitted => ((LiteralData.rowAdmitted_iff _ _).mp admitted).2.1

/-- "Rows stored" has the laws of {name}`WriteLaws`. Proof sketch: {name}`rowAtomLaws`; an admitted row is
stored for the columns ({name}`LiteralData.rowAdmitted_iff`). -/
theorem rowsStoredLaws : WriteLaws Database.RowsStored :=
  rowAtomLaws Table.rowsStoredAtom fun _ _ stored fresh row member =>
    (fresh row member).elim (stored row) fun admitted => ((LiteralData.rowAdmitted_iff _ _).mp admitted).2.2.1

/-- "Rows aliased" has the laws of {name}`WriteLaws`. Proof sketch: {name}`rowAtomLaws`; an admitted row
is aliased for the alias of the entry ({name}`LiteralData.rowAdmitted_iff`). -/
theorem rowsAliasedLaws : WriteLaws Database.RowsAliased :=
  rowAtomLaws Table.rowsAliasedAtom fun _ _ aliased fresh row member =>
    (fresh row member).elim (aliased row) fun admitted => ((LiteralData.rowAdmitted_iff _ _).mp admitted).2.2.2

end Belay.Sqlite.Model
