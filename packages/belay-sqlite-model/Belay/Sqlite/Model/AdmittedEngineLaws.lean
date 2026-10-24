import Belay.Sqlite.Model.AdmittedPlainWrites
import Belay.Sqlite.Model.DatabaseShapedLaws
import Belay.Sqlite.Model.RowEngineWrites

set_option doc.verso true

/-! The row engine keeps three atoms of {lit}`Database.Admitted` (ADR 0022, D3, slice 4): "rowids
distinct", "rows shaped" and "catalog supported". Each has the laws of {lit}`WriteLaws`, so
{lit}`rowsKeys_holds` and {lit}`dropKeys_holds` apply. The row engine passes the checks of a write
({lit}`LiteralData.constraints` and {lit}`LiteralData.rowidsDistinct`) before it stores a table, and
it writes only to positions that have a table, except for a DELETE, which stores a sublist. "Rowids
in range", "rows wide", "rows stored" and "rows aliased" have their laws in {lit}`AdmittedRowLaws`: the
engine writes only rows that {lit}`LiteralData.rowAdmitted` accepts, or rows that were there. -/

namespace Belay.Sqlite.Model

/-- "Rowids distinct" has the facts of {name}`TableFacts`. Proof sketch: a sublist keeps the rowids
distinct ({name}`Table.RowidsDistinct.frame`); a table that passed the check of a write passed
{name}`LiteralData.rowidsDistinct` ({name}`passed_rowidsDistinct`). -/
theorem rowidsDistinctFacts : TableFacts fun _ _ table => Table.RowidsDistinct table where
  sublist _ _ _ _ distinct same sub := Table.rowidsDistinctAtom.sublist _ _ distinct same sub
  constraints _ _ _ passed := passed_rowidsDistinct passed

/-- For every database and position: if the row list at the position is empty, storing an empty row list
there gives the database. Proof sketch: a position past the row lists is unchanged
({name}`List.set_eq_of_length_le`); otherwise the list at the position is already empty. -/
theorem Database.setRows_nil_of_getD {database : Database} {position : Nat}
    (empty : database.rows.getD position [] = []) : database.setRows position [] = database := by
  unfold Database.setRows
  congr 1
  rcases Nat.lt_or_ge position database.rows.length with below | above
  · have atPosition : database.rows[position] = [] := by simpa [List.getD_eq_getElem?_getD, below] using empty
    rw [← atPosition]
    exact List.set_getElem_self below
  · exact List.set_eq_of_length_le above

/-- "Rows shaped" has the laws of {name}`WriteLaws`. Proof sketch: a write at a position with a table is
{name}`Database.RowsShaped.setRows`. A DELETE at a position without a table stores a sublist of an empty
row list, which is the database ({name}`Database.setRows_nil_of_getD`). -/
theorem rowsShapedLaws : WriteLaws Database.RowsShaped where
  sublist database position change shaped sub := by
    cases found : database.table position with
    | some table => exact shaped.setRows found _
    | none =>
      have absent : database.catalog.tableAt position = none := by simpa [Database.table] using found
      have empty := shaped.2 position absent
      have changed : change (database.rows.getD position []) = [] := by
        rw [empty]
        exact List.sublist_nil.mp (sub [])
      rw [changed, Database.setRows_nil_of_getD empty]
      exact shaped
  write database position table rows shaped found _ _ := shaped.setRows found rows

/-- For every limits, "the catalog is valid under the limits" has the laws of {name}`WriteLaws`. Proof
sketch: {name}`Database.setRows` keeps the catalog. -/
theorem catalogSupportedLaws (limits : Limits) : WriteLaws fun database => database.catalog.Valid limits where
  sublist _ _ _ valid _ := valid
  write _ _ _ _ valid _ _ _ := valid

/-- For every property of databases with the laws of {name}`WriteLaws`, rules, clock value, target, work,
database, flag and algorithm: if the database has the property, the effect of {name}`rowsKeys` satisfies it
({name}`Effect.Satisfies`): the database of a success and that of an error with
{name}`ExecutionError.constraintFail` have the property, and any other error requires nothing. Proof
sketch: {name}`rowsKeys_holds` for the database of the effect. -/
theorem rowsKeys_satisfies {invariant : Database → Prop} (laws : WriteLaws invariant) (rules : Resolved.WriteRules)
    (clock : Int) (target : Nat) (work : RowWork) {database : Database} (holds : invariant database) (plain : Bool)
    (algorithm : Option ConflictAlgorithm) :
    (rowsKeys rules clock target work database plain algorithm).effect.Satisfies invariant :=
  Effect.satisfies_of_effectDatabase (rowsKeys_holds laws rules clock target work holds plain algorithm)

end Belay.Sqlite.Model
