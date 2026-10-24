import Belay.Sqlite.Model.ResolveReadsBelow
import Belay.Sqlite.Model.Resolution.TableChecks

set_option doc.verso true

/-! The CHECK lemma for CREATE TABLE (ADR 0022, D3, slice 4): the CHECK constraints that
resolution gives for a table read only columns of the table. {lit}`ResolveReadsBelow` has the
lemma for one expression; this file follows it through the resolution of the constraints.
"Reads below the width" means that {lit}`Expr.any` of {lit}`Expr.isColumnFrom` for the width is
false. -/

namespace Belay.Sqlite.Model

open Resolved

/-- For every function that can fail, list and result list: if mapping the function over the list
gives the results, every result is the result of the function on a member of the list.
Proof sketch: induction over the list. -/
theorem mapM_ok_mem {ε α β : Type} (f : α → Except ε β) : ∀ {xs : List α} {ys : List β},
    xs.mapM f = .ok ys → ∀ y ∈ ys, ∃ x ∈ xs, f x = .ok y
  | [], ys, h => by
    simp only [List.mapM_nil, pure, Except.pure, Except.ok.injEq] at h; subst h; simp
  | x :: xs, ys, h => by
    simp only [List.mapM_cons, exceptBind_eq_ok] at h
    obtain ⟨y, hy, rest, hr, same⟩ := h
    simp only [pure, Except.pure, Except.ok.injEq] at same; subst same
    intro z hz
    rcases List.mem_cons.mp hz with rfl | hz
    · exact ⟨x, List.mem_cons_self, hy⟩
    · obtain ⟨w, hw, hf⟩ := mapM_ok_mem f hr z hz
      exact ⟨w, List.mem_cons_of_mem _ hw, hf⟩

/-- For every function that can fail and keeps or drops each result, list and result list: if
the filtering map gives the results, every result is a kept result of the function on a member of
the list. Proof sketch: induction over the list; a dropped result adds nothing. -/
theorem filterMapM_ok_mem {ε α β : Type} (f : α → Except ε (Option β)) : ∀ {xs : List α} {ys : List β},
    xs.filterMapM f = .ok ys → ∀ y ∈ ys, ∃ x ∈ xs, f x = .ok (some y)
  | [], ys, h => by
    simp only [List.filterMapM, List.filterMapM.loop, pure, Except.pure, Except.ok.injEq] at h; subst h; simp
  | x :: xs, ys, h => by
    rw [List.filterMapM_cons] at h
    simp only [exceptBind_eq_ok] at h
    obtain ⟨o, ho, h⟩ := h
    cases o with
    | none =>
      simp only at h
      intro z hz
      obtain ⟨w, hw, hf⟩ := filterMapM_ok_mem f h z hz
      exact ⟨w, List.mem_cons_of_mem _ hw, hf⟩
    | some b =>
      simp only [exceptBind_eq_ok] at h
      obtain ⟨rest, hr, same⟩ := h
      simp only [pure, Except.pure, Except.ok.injEq] at same; subst same
      intro z hz
      rcases List.mem_cons.mp hz with rfl | hz
      · exact ⟨x, List.mem_cons_self, ho⟩
      · obtain ⟨w, hw, hf⟩ := filterMapM_ok_mem f hr z hz
        exact ⟨w, List.mem_cons_of_mem _ hw, hf⟩

open Resolved

/-- For every scope that ends below a width, double-quote setting, condition, label and check: if
the CHECK constraint resolves to the check ({name}`resolveCheck`), its condition reads below the
width. A refused constraint requires nothing. Proof sketch: the condition is the resolved operand
({name}`resolveOperand_below`). -/
theorem resolveCheck_below {width : Nat} {scope : Scope} (bounded : scope.Bounded width) {dqs : Bool}
    {condition : Syntax.Expr} {label : String} {check : CheckConstraint}
    (ok : resolveCheck dqs scope condition label = .ok check) :
    check.condition.any (Expr.isColumnFrom width) = false := by
  simp only [resolveCheck, exceptBind_eq_ok, condition_eq_ok] at ok
  obtain ⟨_, _, resolved, ⟨operand, ho, rfl⟩, ok⟩ := ok
  have := resolveOperand_below bounded dqs {} true condition operand ho
  split at ok
  · cases ok
  · cases ok; exact this

/-- For every scope that ends below a width and column definition: if the CHECK constraints of
the column resolve ({name}`columnChecks`), the condition of each reads below the width. A refused
constraint requires nothing. Proof sketch: a check of the list comes from a CHECK constraint of the
definition, whose condition {name}`resolveCheck_below` bounds; the other constraints give no check. -/
theorem columnChecks_below {width : Nat} {scope : Scope} (bounded : scope.Bounded width) {dqs : Bool}
    {definition : Syntax.ColumnDefinition} {checks : List CheckConstraint}
    (ok : columnChecks dqs scope definition = .ok checks) :
    ∀ check ∈ checks, check.condition.any (Expr.isColumnFrom width) = false := by
  intro check member
  obtain ⟨⟨constraint, item⟩, _, hf⟩ := filterMapM_ok_mem _ ok check member
  cases constraint with
  | check condition label =>
    simp only [exceptFmap_eq_ok, exceptMapError_eq_ok, Option.some.injEq] at hf
    obtain ⟨found, hc, rfl⟩ := hf
    exact resolveCheck_below bounded hc
  | notNull _ | primaryKey _ _ | unique _ | default _ _ | collate _ | references _ _ _ _ | generated _ _
  | deferral _ => cases hf

/-- For every scope that ends below a width, table, definitions and constraints: if every column of
the table beyond the definitions has no CHECK constraint and the CHECK constraints resolve to the
table {lit}`result` ({name}`resolveTableChecks`), the condition of every constraint in
{name}`CatalogTable.allChecks` of {lit}`result` reads below the width. A refused constraint
requires nothing. Proof sketch: a constraint is one of the resolved column constraints, one of the
resolved table constraints, or one of a column that was not resolved, which has none. -/
theorem resolveTableChecks_below {width : Nat} {scope : Scope} (bounded : scope.Bounded width) {dqs : Bool}
    {table : CatalogTable} {definitions : List Syntax.ColumnDefinition} {constraints : List Syntax.TableConstraint}
    {result : CatalogTable}
    (unchecked : ∀ column ∈ table.columns.drop definitions.length, column.checks = [])
    (ok : resolveTableChecks dqs scope table definitions constraints = .ok result) :
    ∀ check ∈ result.allChecks, check.condition.any (Expr.isColumnFrom width) = false := by
  simp only [resolveTableChecks, exceptBind_eq_ok] at ok
  obtain ⟨checked, hc, tableChecks, ht, same⟩ := ok
  cases same
  intro check member
  simp only [CatalogTable.allChecks, List.mem_append, List.mem_flatMap] at member
  rcases member with ⟨column, inColumns, inChecks⟩ | inTable
  · rcases inColumns with fromChecked | fromRest
    · obtain ⟨⟨⟨original, definition⟩, position⟩, _, hf⟩ := mapM_ok_mem _ hc column fromChecked
      simp only [exceptFmap_eq_ok, exceptMapError_eq_ok] at hf
      obtain ⟨checks, hk, rfl⟩ := hf
      exact columnChecks_below bounded hk check inChecks
    · simp [unchecked column fromRest] at inChecks
  · obtain ⟨⟨constraint, item⟩, _, hf⟩ := filterMapM_ok_mem _ ht check inTable
    cases constraint with
    | check condition label =>
      simp only [exceptFmap_eq_ok, exceptMapError_eq_ok, Option.some.injEq] at hf
      obtain ⟨found, hk, rfl⟩ := hf
      exact resolveCheck_below bounded hk
    | primaryKey _ _ | unique _ _ | foreignKey _ _ _ _ _ | deferral _ => cases hf

end Belay.Sqlite.Model
