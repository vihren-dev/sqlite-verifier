import Belay.Sqlite.Model.CatalogTableLaws
import Belay.Sqlite.Model.DatabaseLaws

set_option doc.verso true

/-! The validity of a catalog after ALTER TABLE ADD COLUMN (ADR 0022, D3, slice 4): the table
gets one more column, so every key and every CHECK of the table, and every index on it, still
reads only columns below the width. -/

namespace Belay.Sqlite.Model

open Resolved

/-- For every width, larger width and expression: if the expression reads no column at or after the
width ({name}`Expr.isColumnFrom`, {name}`Expr.any`), it reads none at or after the larger width.
Proof sketch: induction over the mutual expression and argument types; a column below the width is
below the larger width, and every other node combines its parts. -/
theorem Expr.any_isColumnFrom_mono {width other : Nat} (le : width ≤ other) (expression : Expr)
    (below : expression.any (Expr.isColumnFrom width) = false) :
    expression.any (Expr.isColumnFrom other) = false := by
  induction expression using Expr.rec
    (motive_2 := fun arguments => arguments.any (Expr.isColumnFrom width) = false →
      arguments.any (Expr.isColumnFrom other) = false)
  all_goals simp_all [Expr.any, Arguments.any, Expr.isColumnFrom]
  all_goals omega

/-- For every expression that reads only columns below a width and every larger width, the
expression reads only columns below the larger width ({name}`Expr.readsBelow`). Proof sketch:
{name}`Expr.any_isColumnFrom_mono`. -/
theorem Expr.readsBelow_mono {width other : Nat} (le : width ≤ other) {expression : Expr}
    (below : expression.readsBelow width = true) : expression.readsBelow other = true := by
  simp only [Expr.readsBelow, Bool.not_eq_true'] at below ⊢
  exact Expr.any_isColumnFrom_mono le expression below

/-- For every index, width and larger width: an index that is supported for the width
({name}`CatalogIndex.supported`) is supported for the larger width. Proof sketch: each test of
{name}`CatalogIndex.supported` is a bound on positions or on the columns that an expression reads,
and a bound on the width stays true for a larger width. -/
theorem CatalogIndex.supported_mono {index : CatalogIndex} {width other : Nat}
    (supported : index.supported width = true) (le : width ≤ other) : index.supported other = true := by
  simp only [CatalogIndex.supported, Bool.and_eq_true, List.all_eq_true, decide_eq_true_eq,
    Option.all_eq_true] at supported ⊢
  obtain ⟨⟨⟨nonempty, positions⟩, terms⟩, filter⟩ := supported
  refine ⟨⟨⟨nonempty, fun position member => Nat.lt_of_lt_of_le (positions position member) le⟩, ?_⟩, ?_⟩
  · intro key member
    have := terms key member
    cases hterm : key.term with
    | column _ => simp
    | expression value =>
      rw [hterm] at this
      exact Expr.readsBelow_mono le this
  · intro condition member
    exact Expr.readsBelow_mono le (filter condition member)

/-- For every table, column and limits: if the table is supported, the column fits under the column
limit, its name is new and not a name of the rowid, and its CHECK constraints read only columns below
the new width, then the table with the column appended is supported. Proof sketch: the facts of
{name}`CatalogTable.SupportedFacts` of the old table stay true for the longer column list, and the
new column adds one fact of each kind. -/
theorem CatalogTable.supported_addColumn {limits : Limits} {table : CatalogTable} {column : CatalogColumn}
    (supported : table.supported limits = true) (fits : table.columns.length + 1 ≤ limits.columns)
    (fresh : (columnPosition table.columns column.name).isNone = true) (ordinary : rowidName column.name = false)
    (checks : ∀ check ∈ column.checks, check.condition.readsBelow (table.columns.length + 1) = true) :
    ({ table with columns := table.columns ++ [column] } : CatalogTable).supported limits = true := by
  rw [CatalogTable.supported_iff] at supported ⊢
  obtain ⟨_, _, names, rowid, primary, unique, alias, old⟩ := supported
  have grows : ∀ position, position < table.columns.length → position < table.columns.length + 1 := by omega
  refine ⟨by simp, by simpa using fits, ?_, ?_, ?_, ?_, ?_, ?_⟩
  · simp only [List.map_append, List.map_cons, List.map_nil]
    refine List.nodup_append.mpr ⟨names, by simp, ?_⟩
    intro name inside other single same
    simp only [List.mem_singleton] at single
    subst single
    obtain ⟨found, member, rfl⟩ := List.mem_map.mp inside
    have none := (findPosition_eq_none_iff _ _).mp (Option.map_eq_none_iff.mp (Option.isNone_iff_eq_none.mp fresh))
    have := none found member
    simp [Identifier.sameName, same] at this
  · intro found member
    rcases List.mem_append.mp member with old | new
    · exact rowid found old
    · simp only [List.mem_singleton] at new; subst new; exact ordinary
  · intro position member
    simpa using grows position (primary position member)
  · intro key member
    exact ⟨(unique key member).1, fun position inside => by simpa using grows position ((unique key member).2 position inside)⟩
  · intro position hposition
    obtain ⟨key, off, existing, found, generated, integer⟩ := alias position hposition
    refine ⟨key, off, existing, ?_, generated, integer⟩
    rw [List.getElem?_append_left (List.getElem?_eq_some_iff.mp found).1]
    exact found
  · intro check member
    simp only [CatalogTable.allChecks, List.flatMap_append, List.mem_append, List.flatMap_cons, List.flatMap_nil,
      List.append_nil] at member
    simp only [List.length_append, List.length_singleton]
    rcases member with (older | newer) | table
    · exact Expr.readsBelow_mono (Nat.le_succ _) (old check (by simp [CatalogTable.allChecks, older]))
    · exact checks check newer
    · exact Expr.readsBelow_mono (Nat.le_succ _) (old check (by simp [CatalogTable.allChecks, table]))

end Belay.Sqlite.Model
