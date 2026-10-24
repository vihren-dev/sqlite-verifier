import Belay.Sqlite.Model.AdmittedCellLaws
import Belay.Sqlite.Model.DatabaseFacts
import Belay.Sqlite.Model.RowUpdate
import Belay.Sqlite.Model.StoreValueLaws

set_option doc.verso true

/-! The rows of an UPDATE (ADR 0022, D3, slice 4): what {lit}`LiteralData.assignFrom` and
{lit}`LiteralData.movedRowid` keep of the atoms "rows wide", "rows stored" and "rows aliased".
An UPDATE sets the cells of the assigned positions to values stored with the affinity of their
column, computes the generated columns, and then moves the row to the rowid of its alias cell. So
the width stays, the stored form stays, and the alias cell is the rowid when the cell is an
integer, which {lit}`LiteralData.updateMismatch` checks for an assigned alias. The statement
theorems use these laws for UPDATE, and the {lit}`DO UPDATE` of an upsert uses them for its
changed row. -/

namespace Belay.Sqlite.Model
namespace LiteralData

/-- For every property of cells, assignments, context, columns and cells, and start list of
values: if the start list has the property, and setting the stored value of an assignment at its
position keeps it, the fold of the assignments of {name}`assignFrom` over the start list has it.
Proof sketch: {name}`foldl_invariant` over the assignments. -/
theorem assignments_invariant (property : List Value → Prop) (context : Resolved.EvalContext)
    (columns : List CatalogColumn) (assignments : List (Nat × Resolved.Expr)) (cells start : List Value)
    (good : property start)
    (keeps : ∀ values position expression, (position, expression) ∈ assignments → property values →
      property (values.set position (Value.store (positionAffinity columns position) (expression.eval context cells)))) :
    property (assignments.foldl (fun values (position, expression) =>
      values.set position (Value.store (positionAffinity columns position) (expression.eval context cells))) start) :=
  foldl_invariant property _ assignments start good fun values element member same => by
    obtain ⟨position, expression⟩ := element
    exact keeps values position expression member same

/-- For every context, columns, assignments, cells and row, {name}`assignFrom` keeps the number of
cells of the row. Proof sketch: setting a cell keeps the length, and so does
{name}`generatedCells_length`. -/
theorem assignFrom_length (context : Resolved.EvalContext) (columns : List CatalogColumn)
    (assignments : List (Nat × Resolved.Expr)) (cells : List Value) (row : Row) :
    (assignFrom context columns assignments cells row).values.length = row.values.length := by
  unfold assignFrom
  dsimp only
  rw [generatedCells_length]
  exact assignments_invariant (fun values => values.length = row.values.length) context columns assignments cells
    row.values rfl fun _ _ _ _ same => by simp [same]

/-- For every context, columns, assignments, cells and row: if every cell of the row is stored for
its column, every cell of {name}`assignFrom` is. No condition on the width or on the columns of the
assigned positions is needed. Proof sketch: an assigned cell is stored with the affinity of the
column at its position, which is stored again ({name}`Value.store_store`), and a position without a
column imposes nothing; {name}`generatedCells_stored` covers the generated columns. -/
theorem assignFrom_stored (context : Resolved.EvalContext) (columns : List CatalogColumn)
    (assignments : List (Nat × Resolved.Expr)) (cells : List Value) {row : Row} (stored : row.Stored columns) :
    (assignFrom context columns assignments cells row).Stored columns := by
  unfold assignFrom
  refine generatedCells_stored ?_
  refine assignments_invariant (fun values => ∀ (position : Nat) (column : CatalogColumn) (value : Value),
    columns[position]? = some column → values[position]? = some value → Value.store column.affinity value = value)
    context columns assignments cells row.values stored ?_
  intro values changed expression _ good position column value atColumn atCell
  by_cases same : changed = position
  · subst same
    rcases Nat.lt_or_ge changed values.length with below | above
    · rw [List.getElem?_set_self below, Option.some.injEq] at atCell
      subst atCell
      simp only [positionAffinity, atColumn, Option.map_some, Option.getD_some]
      exact Value.store_store _ _
    · rw [List.getElem?_eq_none (by simp; omega)] at atCell
      cases atCell
  · rw [List.getElem?_set_ne same] at atCell
    exact good position column value atColumn atCell

/-- For every context, columns, assignments, cells, row and position: if no assignment sets the
position and the column at the position is not generated, the cell of {name}`assignFrom` at the
position is the cell of the row. Proof sketch: a set at another position keeps the cell, and
{name}`generatedCells_ungenerated` keeps it past the generated columns. -/
theorem assignFrom_unassigned (context : Resolved.EvalContext) (columns : List CatalogColumn)
    (assignments : List (Nat × Resolved.Expr)) (cells : List Value) (row : Row) {position : Nat}
    {column : CatalogColumn} (atColumn : columns[position]? = some column) (ungenerated : column.generated = none)
    (unassigned : ∀ pair ∈ assignments, pair.1 ≠ position) :
    (assignFrom context columns assignments cells row).values[position]? = row.values[position]? := by
  unfold assignFrom
  dsimp only
  rw [generatedCells_ungenerated atColumn ungenerated]
  refine assignments_invariant (fun values => values[position]? = row.values[position]?) context columns assignments
    cells row.values rfl ?_
  intro values changed expression member same
  rw [List.getElem?_set_ne (unassigned _ member)]
  exact same

/-- For every alias and row, {name}`movedRowid` keeps the cells of the row. Proof sketch: it changes
at most the rowid. -/
theorem movedRowid_values (alias : Option Nat) (row : Row) : (movedRowid alias row).values = row.values := by
  unfold movedRowid
  split <;> rfl

/-- For every alias, row and integer: if the cell of the alias is that integer, {name}`movedRowid`
gives the row the integer as its rowid. Proof sketch: the definition, with the cell read. -/
theorem movedRowid_integer {alias : Option Nat} {row : Row} {rowid : Int}
    (cell : alias.bind (row.values[·]?) = some (.integer rowid)) : movedRowid alias row = { row with rowid } := by
  simp [movedRowid, cell]

/-- For every alias, row and integer: if the row has the integer as its alias cell, {name}`movedRowid`
gives a row that is aliased. Proof sketch: the row gets the integer as its rowid, and its cells
stay ({name}`movedRowid_integer`). -/
theorem movedRowid_aliased {alias : Option Nat} {row : Row} {rowid : Int} {position : Nat}
    (found : alias = some position) (cell : row.values[position]? = some (.integer rowid)) :
    (movedRowid alias row).Aliased alias := by
  subst found
  rw [movedRowid_integer (by simpa using cell)]
  intro other same
  cases same
  simpa using cell

/-- For every context, table, assignments, filter and row {lit}`old` of the table that the filter selects:
if {lit}`old` is aliased, the column of the rowid alias is not generated, and
{name}`updateMismatch` is false, then {name}`movedRowid` of {name}`assign` of {lit}`old` is aliased.
Proof sketch: if no assignment sets the alias, its cell stays the integer rowid
({name}`assignFrom_unassigned`); if one sets it, {name}`updateMismatch` is false only when the cell
is an integer; then {name}`movedRowid_aliased`. -/
theorem assign_aliased {context : Resolved.EvalContext} {table : Table} {assignments : List (Nat × Resolved.Expr)}
    {filter : Option Resolved.Expr} {old : Row} (oldMember : old ∈ table.rows)
    (aliased : old.Aliased table.shape.rowidAlias)
    (ungenerated : ∀ position, table.shape.rowidAlias = some position →
      ∃ column, table.shape.columns[position]? = some column ∧ column.generated = none)
    (accepted : updateMismatch context table assignments filter = false) (chosen : selected context filter old = true) :
    (movedRowid table.shape.rowidAlias (assign context table.shape.columns assignments old)).Aliased
      table.shape.rowidAlias := by
  cases hAlias : table.shape.rowidAlias with
  | none => intro position same; cases same
  | some position =>
    obtain ⟨column, atColumn, none⟩ := ungenerated position hAlias
    have cell : ∃ rowid, (assign context table.shape.columns assignments old).values[position]? =
        some (.integer rowid) := by
      by_cases assigned : assignments.any (·.1 == position) = true
      · unfold updateMismatch at accepted
        simp only [hAlias, assigned, Bool.true_and] at accepted
        have noMatch := List.any_eq_false.mp accepted old oldMember
        cases h : (assign context table.shape.columns assignments old).values[position]? with
        | none => simp [chosen, h] at noMatch
        | some value =>
          cases value with
          | integer rowid => exact ⟨rowid, rfl⟩
          | null => simp [chosen, h] at noMatch
          | real _ => simp [chosen, h] at noMatch
          | text _ => simp [chosen, h] at noMatch
          | blob _ => simp [chosen, h] at noMatch
      · have unassigned : ∀ pair ∈ assignments, pair.1 ≠ position := fun pair member same =>
          assigned (List.any_eq_true.mpr ⟨pair, member, by simp [same]⟩)
        simp only [assign]
        rw [assignFrom_unassigned context table.shape.columns assignments old.values old atColumn none unassigned]
        exact ⟨old.rowid, aliased position hAlias⟩
    obtain ⟨rowid, cell⟩ := cell
    exact movedRowid_aliased rfl cell

end LiteralData
end Belay.Sqlite.Model
