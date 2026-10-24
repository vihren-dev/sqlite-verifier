import Belay.Sqlite.Model.RowInsert
import Belay.Sqlite.Model.RowCredit

set_option doc.verso true

/-! The row engine of a write that runs row by row (ADR 0018, D4 and D5): the rows of a DELETE,
an UPDATE or an INSERT in order, each with its foreign keys and the programs of its triggers,
whose own writes run in the engine with one less fuel. -/

namespace Belay.Sqlite.Model

/-- Run the work in the frame with the links of the catalog, with fuel for the depth of the
nested writes: each nested write of an action or a program runs with one less, and the work is
not described without fuel, as SQLite fails beyond its trigger depth limit. The rows run in
order ({name}`deleteRow`, {name}`updateRow`, {name}`insertRow`). -/
def runRows (catalog : Catalog) (links : List ForeignKeyLink) : Nat → RowFrame → RowWork → KeyState → Except KeyStop KeyState
  | 0, _, _, _ => throw .undescribed
  | fuel + 1, frame, .delete position rowids record ignore fire, state =>
    rowids.foldlM (deleteRow catalog links (NestedRun.credited (runRows catalog links fuel)) frame position record ignore fire) state
  | fuel + 1, frame, .update position change assigned changed rowids record, state =>
    rowids.foldlM (updateRow catalog links (NestedRun.credited (runRows catalog links fuel)) frame position change assigned changed record) state
  | fuel + 1, frame, .insert position rows policy clauses multiWrite record, state =>
    rows.foldlM (insertRow catalog links (NestedRun.credited (runRows catalog links fuel)) frame position policy clauses multiWrite record) state

end Belay.Sqlite.Model
