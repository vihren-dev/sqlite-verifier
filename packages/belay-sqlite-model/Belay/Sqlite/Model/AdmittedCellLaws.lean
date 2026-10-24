import Belay.Sqlite.Model.LiteralData
import Belay.Sqlite.Model.StoreValueLaws

set_option doc.verso true

/-! The cells of a written row (ADR 0022, D3, slice 4): what {lit}`LiteralData.generatedCells` and
{lit}`LiteralData.newCells` keep of a list of cells. {lit}`generatedCells` sets the cell of each
generated column to a value that is stored for its own column. So it keeps the width of the cells,
the stored form of every cell, and the cell of every column that is not generated. {lit}`newCells`
first sets the cell of the rowid alias to the integer rowid, and then it is {lit}`generatedCells`.
So it also keeps the width, gives the alias cell when the alias column is not generated, and keeps
the stored form when the alias column has INTEGER affinity. The statement theorems of "rows wide",
"rows stored" and "rows aliased" use these laws for INSERT and UPDATE. -/

namespace Belay.Sqlite.Model
namespace LiteralData

/-- For every property of values and function, list and start value: if the start value has the
property and each step from a value with the property, with an element of the list, keeps it, then
the fold of the steps over the list ({lit}`List.foldl`) has it. Proof sketch: induction on the list. -/
theorem foldl_invariant {α β : Type} (property : α → Prop) (step : α → β → α) (list : List β) :
    ∀ start, property start → (∀ value element, element ∈ list → property value → property (step value element)) →
      property (list.foldl step start) := by
  induction list with
  | nil => intro start holds _; exact holds
  | cons first rest induction =>
    intro start holds keeps
    exact induction _ (keeps start first (List.mem_cons_self ..) holds)
      fun value element member good => keeps value element (List.mem_cons_of_mem _ member) good

/-- For every columns, cells and property of cells: if the cells have the property, and setting the
cell of a generated column at its position to any value stored with that column's affinity keeps
it, then {name}`generatedCells` of the cells has the property. Proof sketch: the computation is a
fold of such sets ({name}`foldl_invariant`), and each set is at a position whose column is
generated, with the affinity of the column ({name}`List.mem_zipIdx_iff_getElem?`). -/
theorem generatedCells_invariant {columns : List CatalogColumn} {values : List Value}
    (property : List Value → Prop) (start : property values)
    (keeps : ∀ cells position column value, columns[position]? = some column → column.generated.isSome = true →
      property cells → property (cells.set position (Value.store column.affinity value))) :
    property (generatedCells columns values) := by
  unfold generatedCells
  refine foldl_invariant property _ _ values start fun cells _ _ good => ?_
  refine foldl_invariant property _ _ cells good fun cells element member good => ?_
  obtain ⟨⟨column, position⟩, member, found⟩ := List.mem_filterMap.mp member
  have atPosition := List.mem_zipIdx_iff_getElem?.mp member
  cases generated : column.generated with
  | none => simp [generated] at found
  | some how =>
    simp only [generated, Option.map_some, Option.some.injEq] at found
    subst found
    exact keeps cells position column _ atPosition (by simp [generated]) good

/-- For every columns and cells, {name}`generatedCells` keeps the number of cells. Proof sketch:
{name}`generatedCells_invariant`; setting a cell keeps the length. -/
theorem generatedCells_length (columns : List CatalogColumn) (values : List Value) :
    (generatedCells columns values).length = values.length :=
  generatedCells_invariant (fun cells => cells.length = values.length) rfl
    fun _ _ _ _ _ _ same => by simp [same]

/-- For every columns and cells: if every cell is stored for its column (the cells and the columns
meet at the positions where both exist), every cell of {name}`generatedCells` is. Proof sketch:
{name}`generatedCells_invariant`; the new cell at a generated column is stored with the affinity of
that column, and {name}`Value.store_store` says that this is its stored form; every other cell
stays. -/
theorem generatedCells_stored {columns : List CatalogColumn} {values : List Value}
    (stored : ∀ (position : Nat) (column : CatalogColumn) (value : Value), columns[position]? = some column →
      values[position]? = some value → Value.store column.affinity value = value) :
    ∀ (position : Nat) (column : CatalogColumn) (value : Value), columns[position]? = some column →
      (generatedCells columns values)[position]? = some value → Value.store column.affinity value = value := by
  refine generatedCells_invariant (fun cells : List Value => ∀ (position : Nat) (column : CatalogColumn) (value : Value),
    columns[position]? = some column → cells[position]? = some value → Value.store column.affinity value = value) stored ?_
  intro cells changed generatedColumn written found _ good position column value atColumn atCell
  by_cases same : changed = position
  · subst same
    rw [found, Option.some.injEq] at atColumn
    subst atColumn
    rcases Nat.lt_or_ge changed cells.length with below | above
    · rw [List.getElem?_set_self below, Option.some.injEq] at atCell
      subst atCell
      exact Value.store_store _ _
    · rw [List.getElem?_eq_none (by simp; omega)] at atCell
      cases atCell
  · rw [List.getElem?_set_ne same] at atCell
    exact good position column value atColumn atCell

/-- For every columns, cells and position: if the column at the position is not generated, the cell
of {name}`generatedCells` at the position is the cell before. Proof sketch:
{name}`generatedCells_invariant`; a set is at the position of a generated column, which is not the
position of a column that is not generated. -/
theorem generatedCells_ungenerated {columns : List CatalogColumn} {values : List Value} {position : Nat}
    {column : CatalogColumn} (atColumn : columns[position]? = some column) (ungenerated : column.generated = none) :
    (generatedCells columns values)[position]? = values[position]? := by
  refine generatedCells_invariant (fun cells => cells[position]? = values[position]?) rfl ?_
  intro cells changed other value found generated same
  have different : changed ≠ position := by
    intro equal
    subst equal
    rw [atColumn, Option.some.injEq] at found
    subst found
    simp [ungenerated] at generated
  rw [List.getElem?_set_ne different]
  exact same

/-- For every table, cells and rowid, {name}`newCells` keeps the number of cells. Proof sketch:
setting the alias cell keeps the length ({name}`List.length_set`), and so does
{name}`generatedCells_length`. -/
theorem newCells_length (table : Table) (values : List Value) (rowid : Int) :
    (newCells table values rowid).length = values.length := by
  unfold newCells
  rw [generatedCells_length]
  cases table.shape.rowidAlias <;> simp

/-- For every table, cells and rowid: if the table passes {name}`aliasReady` (a rowid alias column has
INTEGER affinity) and every cell of the supplied cells is stored for its column, every cell of
{name}`newCells` is. Proof sketch: the alias cell is the integer rowid, which is stored under INTEGER
affinity; the other cells are the supplied cells; {name}`generatedCells_stored` covers the generated
columns. -/
theorem newCells_stored {table : Table} {values : List Value} {rowid : Int}
    (ready : aliasReady table.shape = true)
    (stored : ∀ (position : Nat) (column : CatalogColumn) (value : Value), table.shape.columns[position]? = some column →
      values[position]? = some value → Value.store column.affinity value = value) :
    ∀ (position : Nat) (column : CatalogColumn) (value : Value), table.shape.columns[position]? = some column →
      (newCells table values rowid)[position]? = some value → Value.store column.affinity value = value := by
  unfold newCells
  refine generatedCells_stored ?_
  cases hAlias : table.shape.rowidAlias with
  | none => exact stored
  | some alias =>
    intro position column value atColumn atCell
    by_cases same : alias = position
    · subst same
      simp only [aliasReady, hAlias, Option.all_some, atColumn, Option.any_some, beq_iff_eq] at ready
      rcases Nat.lt_or_ge alias values.length with below | above
      · rw [List.getElem?_set_self below, Option.some.injEq] at atCell
        subst atCell
        rw [ready]
        rfl
      · rw [List.getElem?_eq_none (by simp; omega)] at atCell
        cases atCell
    · rw [List.getElem?_set_ne same] at atCell
      exact stored position column value atColumn atCell

/-- For every table, cells and rowid: if the column of a rowid alias is not generated, and the supplied
cells have as many cells as the table has columns, the cell of {name}`newCells` at the alias is the
integer rowid. Without an alias nothing is required. Proof sketch: the alias cell is set below the
width; {name}`generatedCells_ungenerated` keeps it. -/
theorem newCells_aliased {table : Table} {values : List Value} {rowid : Int}
    (ungenerated : ∀ position, table.shape.rowidAlias = some position →
      ∃ column, table.shape.columns[position]? = some column ∧ column.generated = none)
    (wide : values.length = table.shape.columns.length) :
    ∀ position, table.shape.rowidAlias = some position → (newCells table values rowid)[position]? = some (.integer rowid) := by
  intro position hAlias
  obtain ⟨column, atColumn, none⟩ := ungenerated position hAlias
  have below : position < values.length := by
    rw [wide]
    exact (List.getElem?_eq_some_iff.mp atColumn).1
  unfold newCells
  rw [generatedCells_ungenerated atColumn none]
  simp only [hAlias]
  exact List.getElem?_set_self below

end LiteralData
end Belay.Sqlite.Model
