import Belay.Sqlite.Model.DatabaseLaws
import Belay.Sqlite.Model.ExprAppendLaws
import Belay.Sqlite.Model.KeysUniqueFrame
import Belay.Sqlite.Model.StatementStep

set_option doc.verso true

/-! The theorem of the atom "keys unique" (ADR 0022, D3, slice 2) for ADD COLUMN. ADD COLUMN
appends a cell to each row of its table. The atom holds after it when each row has one cell for
each old column and each unique key of the table reads only the old columns: then each key has
the same value on a row before and after, and the keys of the catalog do not change. The task
file of the slice gives a counterexample for each of the two conditions. -/

namespace Belay.Sqlite.Model

/-- Whether a key term reads only columns below the width: a column below the width, or an
expression that reads only such columns ({name}`Resolved.Expr.readsBelow`). -/
def KeyTerm.readsBelow (width : Nat) : KeyTerm → Bool
  | .column position => decide (position < width)
  | .expression value => value.readsBelow width

/-- Whether a unique key reads only columns below the width: each term
({name}`KeyTerm.readsBelow`), and the filter when it has one. -/
def UniqueKey.readsBelow (width : Nat) (key : UniqueKey) : Bool :=
  key.terms.all (·.term.readsBelow width) && key.filter.all (·.readsBelow width)

/-- The condition of ADD COLUMN at the position for the given database: if the position holds a
table, both hold:
* each row of the table has one cell for each column ({name}`Table.RowsWide`);
* each unique key of the position ({name}`Database.keys`) reads only columns below the width of
  the table ({name}`UniqueKey.readsBelow`).

A position without a table requires nothing. The first is an atom of {lit}`Database.Admitted`,
and the keys of a supported catalog ({name}`CatalogIndex.supported`, {name}`supportedKey`) read
only columns below the width; this file does not prove either fact. -/
def Database.AddColumnCondition (database : Database) (target : Nat) : Prop :=
  ∀ table, database.table target = some table →
    table.RowsWide ∧ ∀ key ∈ database.keys target table, key.readsBelow table.shape.columns.length = true

/-- For every row with at least the width cells, appended cells, and key term that reads only
columns below the width: the term has the same value ({name}`LiteralData.termValue`) on the row
with the cells appended. Proof sketch: a column below the width is a cell of the row, and an
expression is {name}`Resolved.Expr.eval_append`. -/
theorem LiteralData.termValue_append {width : Nat} {row : Row} (wide : width ≤ row.values.length) (extra : List Value)
    {term : KeyTerm} (below : term.readsBelow width = true) :
    termValue (row.appendValues extra) term = termValue row term := by
  cases term with
  | column position =>
    simp only [KeyTerm.readsBelow, decide_eq_true_eq] at below
    simp [termValue, read, Row.appendValues, List.getElem?_append_left (Nat.lt_of_lt_of_le below wide)]
  | expression value =>
    simp only [termValue, Row.appendValues,
      Resolved.Expr.eval_append _ (Resolved.EvalContext.plain_rowFree 0) row.values extra wide below]

/-- For every two rows with at least the width cells, appended cells, and unique key that reads
only columns below the width: the rows with the cells appended conflict on the key
({name}`LiteralData.keyEqual`) exactly when the rows do. Proof sketch: the filter
({name}`Resolved.Expr.eval_append`) and each term ({name}`LiteralData.termValue_append`) have
the same value on both rows. -/
theorem LiteralData.keyEqual_append {width : Nat} {first second : Row} (firstWide : width ≤ first.values.length)
    (secondWide : width ≤ second.values.length) (extra : List Value) {key : UniqueKey}
    (below : key.readsBelow width = true) :
    keyEqual key (first.appendValues extra) (second.appendValues extra) = keyEqual key first second := by
  simp only [UniqueKey.readsBelow, Bool.and_eq_true, List.all_eq_true] at below
  have applies : ∀ row : Row, width ≤ row.values.length → keyApplies key (row.appendValues extra) = keyApplies key row := by
    intro row wide
    unfold keyApplies
    cases filter : key.filter with
    | none => rfl
    | some condition =>
      have reads : condition.readsBelow width = true := by simpa [filter] using below.2
      simp only [Row.appendValues, Resolved.Expr.eval_append _ (Resolved.EvalContext.plain_rowFree 0) row.values extra wide reads]
  unfold keyEqual
  rw [applies first firstWide, applies second secondWide]
  congr 1
  rw [Bool.eq_iff_iff]
  simp only [List.all_eq_true]
  exact forall_congr' fun term => imp_congr_right fun member => by
    rw [termValue_append firstWide extra (below.1 term member), termValue_append secondWide extra (below.1 term member)]

/-- For every list, position, element and function: if the function gives none for the element,
and gives none for the element of the list at the position or the list has no element there,
{lit}`List.filterMap` of the list with the element set at the position is that of the list. A
position past the end leaves the list as it is. Proof sketch: induction on the list; only the element at the
position changes, and both give none. -/
theorem filterMap_set_none {α β} (function : α → Option β) (element : α) (none : function element = .none) :
    ∀ (list : List α) (position : Nat), (list[position]?).bind function = .none →
      (list.set position element).filterMap function = list.filterMap function
  | [], _, _ => rfl
  | head :: rest, 0, old => by simp_all
  | head :: rest, position + 1, old => by
    simp only [List.set_cons_succ, List.filterMap_cons]
    rw [filterMap_set_none function element none rest position (by simpa using old)]

/-- For every catalog, two positions, column and table entry: the unique keys of a position for
the entry ({name}`Catalog.uniqueKeys`) are the same after {name}`Catalog.addColumn`. Proof
sketch: ADD COLUMN replaces a table entry by a table entry ({name}`filterMap_set_none`), and the
catalog adds to the keys only its unique indexes. -/
theorem Catalog.uniqueKeys_addColumn (catalog : Catalog) (target position : Nat) (column : CatalogColumn)
    (shape : CatalogTable) : (catalog.addColumn target column).uniqueKeys position shape = catalog.uniqueKeys position shape := by
  unfold Catalog.uniqueKeys
  congr 1
  unfold Catalog.addColumn
  split
  · rename_i name table found
    exact filterMap_set_none _ _ rfl catalog target (by simp [found])
  all_goals rfl

/-- For every catalog, position, table entry and column: if each unique key of the position for
the entry reads only columns below its width ({name}`UniqueKey.readsBelow`), the unique keys of
the position for the entry with the column appended are the same. Proof sketch: a key of the
primary key or of a UNIQUE constraint reads only its columns, which are below the width, so each
keeps its collation ({name}`UniqueKey.ofColumns`); the indexes do not read the entry. -/
theorem Catalog.uniqueKeys_appendColumn (catalog : Catalog) (position : Nat) (shape : CatalogTable)
    (column : CatalogColumn)
    (below : ∀ key ∈ catalog.uniqueKeys position shape, key.readsBelow shape.columns.length = true) :
    catalog.uniqueKeys position { shape with columns := shape.columns ++ [column] } = catalog.uniqueKeys position shape := by
  unfold Catalog.uniqueKeys at below ⊢
  congr 1
  apply List.map_congr_left
  intro positions member
  have reads := below _ (List.mem_append_left _ (List.mem_map_of_mem member))
  simp only [UniqueKey.ofColumns, UniqueKey.readsBelow, List.all_map, List.all_eq_true, Function.comp,
    KeyTerm.readsBelow, decide_eq_true_eq, Option.all_none, Bool.and_true] at reads
  simp only [UniqueKey.ofColumns, UniqueKey.mk.injEq, and_true]
  apply List.map_congr_left
  intro place inside
  rw [List.getElem?_append_left (reads place inside)]

/-- For every database, position, column and value: if the database satisfies
{name}`Database.KeysUnique` and meets the condition of ADD COLUMN at the position
({name}`Database.AddColumnCondition`, which requires nothing when the position holds no table),
the database after {name}`Database.addColumn` satisfies
{name}`Database.KeysUnique`. Proof sketch: the keys of every position stay the same
({name}`Catalog.uniqueKeys_addColumn`, {name}`Catalog.uniqueKeys_appendColumn`); the table of
the position gets one cell in each row, which changes no conflict on its keys
({name}`LiteralData.keyEqual_append`), and every other table stays. A position without a table
has no table after ADD COLUMN. -/
theorem Database.KeysUnique.addColumn {database : Database} (unique : database.KeysUnique) {target : Nat}
    (condition : database.AddColumnCondition target) (column : CatalogColumn) (value : Value) :
    (database.addColumn target column value).KeysUnique := by
  intro position table present
  by_cases same : position = target
  · subst same
    cases found : database.table position with
    | none =>
      exfalso
      have absent : database.catalog.tableAt position = none := by simpa [Database.table] using found
      have still : (database.catalog.addColumn position column).tableAt position = none := by
        unfold Catalog.addColumn
        split
        · rename_i name shape entry
          simp [Catalog.tableAt, entry] at absent
        all_goals exact absent
      simp [Database.table, Database.addColumn, still] at present
    | some old =>
      rw [Database.table_addColumn column value found, Option.some.injEq] at present
      subst present
      obtain ⟨wide, below⟩ := condition old found
      have keys := Catalog.uniqueKeys_appendColumn database.catalog position old.shape column below
      simp only [Table.appendColumns, List.map_cons, List.map_nil, Database.addColumn, Catalog.uniqueKeys_addColumn, keys]
      intro key member
      rw [List.pairwise_map]
      refine (unique position old found key member).imp_of_mem fun {first second} atFirst atSecond distinct => ?_
      rw [LiteralData.keyEqual_append (Nat.le_of_eq (wide first atFirst).symm) (Nat.le_of_eq (wide second atSecond).symm)
        _ (below key member)]
      exact distinct
  · rw [Database.table_addColumn_other database column value same] at present
    have kept := unique position table present
    simp only [Database.addColumn, Catalog.uniqueKeys_addColumn]
    exact kept

/-- For every clock value, parameter list, ADD COLUMN and database: if the database satisfies
{name}`Database.KeysUnique` and meets the condition of ADD COLUMN at the target
({name}`Database.AddColumnCondition`), the effect of {name}`runStatement` satisfies
{name}`Effect.KeysUnique`. It assumes nothing about the support check. Proof sketch: every error
keeps the database, and a success is {name}`Database.KeysUnique.addColumn`. -/
theorem runStatement_addColumn_keysUnique (clock : Int) (parameters : List Value) (target : Nat)
    (column : CatalogColumn) {database : Database} (unique : database.KeysUnique)
    (condition : database.AddColumnCondition target) :
    (runStatement clock parameters (.addColumn target column) database).effect.KeysUnique := by
  simp only [runStatement, step]
  repeat' split
  all_goals first
    | exact Effect.keysUnique_of_effectDatabase (unique.addColumn condition _ _)
    | exact Effect.keysUnique_of_database unique rfl

end Belay.Sqlite.Model
