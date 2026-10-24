import Belay.Sqlite.Model.ResolveCallsBelow

set_option doc.verso true

/-! The CHECK lemma (ADR 0022, D3, slice 4): an expression that resolution builds over a scope
whose sources all end below a width reads only columns below the width. The statements are for
every {lit}`shapes` of subqueries, every {lit}`misuse` flag and every setting of double-quoted
strings, because a name is the only way to read a column. The lemma gives the facts about the
CHECK constraints and the index terms of {lit}`CatalogTable.supported` and
{lit}`CatalogIndex.supported`. In this file "reads below the width" means that {lit}`Expr.any` of
{lit}`Expr.isColumnFrom` for the width is false. -/

namespace Belay.Sqlite.Model

open Resolved

mutual
/-- For every scope that ends below a width, subquery shapes, expression of the syntax and
operand: if resolution gives the operand ({name}`resolveOperand`), the operand reads only columns
below the width. A refused expression gives no operand and requires nothing. Proof sketch:
structural recursion over the expression; a name reads the positions of its resolution, which are
below the width ({name}`Scope.resolveName_below`, {name}`Scope.resolveQualified_below`), and every
other form builds its expression from the resolved parts. -/
theorem resolveOperand_below {width : Nat} {scope : Scope} (bounded : scope.Bounded width) (dqs : Bool)
    (shapes : SubqueryShapes) (misuse : Bool) :
    (e : Syntax.Expr) → ∀ operand, resolveOperand dqs scope shapes misuse e = .ok operand →
      operand.1.any (Expr.isColumnFrom width) = false
  | .identifier name quote, operand, ok => by
    simp only [resolveOperand] at ok
    have named := Scope.resolveName_below bounded name
    cases found : scope.resolveName name with
    | found source reads => rw [found] at ok named; exact nameRead_below named ok
    | missing =>
      simp only [found] at ok
      repeat' split at ok
      all_goals first | (cases ok; done) | (cases ok; simp_all [Expr.any, Expr.isColumnFrom]; done)
    | ambiguous => simp only [found] at ok; cases ok
  | .qualified source column, operand, ok => by
    simp only [resolveOperand] at ok
    have named := Scope.resolveQualified_below bounded source column
    cases found : scope.resolveQualified source column with
    | found source reads => rw [found] at ok named; exact nameRead_below named ok
    | missing =>
      simp only [found] at ok
      repeat' split at ok <;> cases ok
    | ambiguous => simp only [found] at ok; cases ok
  | .compare operator left right, operand, ok => by
    simp only [resolveOperand, exceptBind_eq_ok, exceptMapError_eq_ok] at ok
    obtain ⟨a, ha, b, hb, ok⟩ := ok
    have ia := resolveOperand_below bounded dqs shapes misuse left a ha
    have ib := resolveOperand_below bounded dqs shapes misuse right b hb
    split at ok <;> cases ok <;> (try split) <;> simp_all [Expr.any, Expr.isColumnFrom]
  | .collate inner name, operand, ok => by
    simp only [resolveOperand, exceptBind_eq_ok, exceptMapError_eq_ok] at ok
    obtain ⟨a, ha, ok⟩ := ok
    have ia := resolveOperand_below bounded dqs shapes misuse inner a ha
    split at ok <;> cases ok <;> exact ia
  | .and left right, operand, ok | .or left right, operand, ok => by
    simp only [resolveOperand, exceptBind_eq_ok, condition_eq_ok] at ok
    obtain ⟨a, ⟨oa, ha, rfl⟩, b, ⟨ob, hb, rfl⟩, ok⟩ := ok
    have ia := resolveOperand_below bounded dqs shapes misuse left oa ha
    have ib := resolveOperand_below bounded dqs shapes misuse right ob hb
    cases ok; simp_all [Expr.any, Expr.isColumnFrom]
  | .not inner, operand, ok => by
    simp only [resolveOperand, exceptBind_eq_ok, condition_eq_ok] at ok
    obtain ⟨a, ⟨oa, ha, rfl⟩, ok⟩ := ok
    have ia := resolveOperand_below bounded dqs shapes misuse inner oa ha
    cases ok; simp_all [Expr.any, Expr.isColumnFrom]
  | .isNull inner _, operand, ok | .cast inner _, operand, ok | .positive inner, operand, ok => by
    simp only [resolveOperand, exceptBind_eq_ok, exceptMapError_eq_ok] at ok
    obtain ⟨a, ha, ok⟩ := ok
    have ia := resolveOperand_below bounded dqs shapes misuse inner a ha
    cases ok; simp_all [Expr.any, Expr.isColumnFrom]
  | .arithmetic _ left right, operand, ok | .concatenate left right, operand, ok => by
    simp only [resolveOperand, exceptBind_eq_ok, exceptMapError_eq_ok] at ok
    obtain ⟨a, ha, b, hb, ok⟩ := ok
    have ia := resolveOperand_below bounded dqs shapes misuse left a ha
    have ib := resolveOperand_below bounded dqs shapes misuse right b hb
    cases ok; simp_all [Expr.any, Arguments.any, Expr.isColumnFrom]
  | .numeric text, operand, ok => by
    simp only [resolveOperand, exceptMap_eq_ok] at ok
    obtain ⟨_, -, rfl⟩ := ok; simp [Expr.any, Expr.isColumnFrom]
  | .negate inner, operand, ok => by
    by_cases numbered : ∃ text, inner = .numeric text
    · obtain ⟨text, rfl⟩ := numbered
      simp only [resolveOperand, exceptMap_eq_ok] at ok
      obtain ⟨_, -, rfl⟩ := ok; simp [Expr.any, Expr.isColumnFrom]
    · have unnumbered : ∀ text, inner = .numeric text → False := fun text same => numbered ⟨text, same⟩
      simp only [resolveOperand, exceptBind_eq_ok, exceptMapError_eq_ok] at ok
      obtain ⟨a, ha, ok⟩ := ok
      have ia := resolveOperand_below bounded dqs shapes misuse inner a ha
      cases ok; simp_all [Expr.any, Expr.isColumnFrom]
  | .call name arguments, operand, ok => by
    simp only [resolveOperand, exceptBind_eq_ok] at ok
    obtain ⟨resolved, hr, ok⟩ := ok
    have ir := resolveArguments_below bounded dqs shapes misuse 0 arguments resolved hr
    split at ok
    · cases ok
    · split at ok
      · cases ok; simp [Expr.any, Expr.isColumnFrom]
      · exact callOperand_below ir ok
  | .callStar name, operand, ok => by
    simp only [resolveOperand] at ok
    split at ok
    · cases ok; simp [Expr.any, Expr.isColumnFrom]
    · split at ok <;> cases ok
  | .null, operand, ok | .string _, operand, ok | .blob _, operand, ok | .currentTime _, operand, ok
  | .parameter _, operand, ok => by cases ok; simp [Expr.any, Expr.isColumnFrom]
  | .exists index, operand, ok => by
    simp only [resolveOperand] at ok
    split at ok <;> cases ok; simp [Expr.any, Expr.isColumnFrom]
  | .subquery index, operand, ok => by
    simp only [resolveOperand, exceptMap_eq_ok] at ok
    obtain ⟨_, -, rfl⟩ := ok; simp [Expr.any, Expr.isColumnFrom]
  | .inQuery inner index negated, operand, ok => by
    simp only [resolveOperand, exceptBind_eq_ok, exceptMapError_eq_ok] at ok
    obtain ⟨a, ha, shape, hs, ok⟩ := ok
    have ia := resolveOperand_below bounded dqs shapes misuse inner a ha
    cases ok; simp_all [Expr.any, Expr.isColumnFrom]
  | .inList inner values negated, operand, ok => by
    simp only [resolveOperand, exceptBind_eq_ok, exceptMapError_eq_ok] at ok
    obtain ⟨a, ha, resolved, hr, ok⟩ := ok
    have ia := resolveOperand_below bounded dqs shapes misuse inner a ha
    have ir := resolveArguments_below bounded dqs shapes misuse 0 values resolved hr
    split at ok
    · split at ok
      · cases ok; split <;> simp_all [Expr.any, Expr.isColumnFrom, Arguments.any]
      · cases ok; simp_all [Expr.any, Expr.isColumnFrom]
    · cases ok; simp_all [Expr.any, Expr.isColumnFrom]
  | .between inner low high negated, operand, ok => by
    simp only [resolveOperand, exceptBind_eq_ok, exceptMapError_eq_ok] at ok
    obtain ⟨a, ha, l, hl, h, hh, ok⟩ := ok
    have ia := resolveOperand_below bounded dqs shapes misuse inner a ha
    have il := resolveOperand_below bounded dqs shapes misuse low l hl
    have ih := resolveOperand_below bounded dqs shapes misuse high h hh
    cases ok; split <;> simp_all [Expr.any, Expr.isColumnFrom]
  | .caseOf operands hasBase, operand, ok => by
    simp only [resolveOperand, exceptBind_eq_ok] at ok
    obtain ⟨resolved, hr, ok⟩ := ok
    have ir := resolveCase_below bounded dqs shapes misuse hasBase none 0 (by simp) operands resolved hr
    cases ok; simp_all [Expr.any, Expr.isColumnFrom]
  | .raise .., operand, ok => by cases ok

/-- For every scope that ends below a width, subquery shapes, written arguments and arguments: if
resolution gives the arguments ({name}`resolveArguments`), all of them read only columns below
the width. A refused argument gives no arguments and requires nothing. Proof sketch: induction over
the list, with {name}`resolveOperand_below` for each argument. -/
theorem resolveArguments_below {width : Nat} {scope : Scope} (bounded : scope.Bounded width) (dqs : Bool)
    (shapes : SubqueryShapes) (misuse : Bool) (index : Nat) :
    (es : List Syntax.Expr) → ∀ arguments, resolveArguments dqs scope shapes misuse index es = .ok arguments →
      arguments.any (Expr.isColumnFrom width) = false
  | [], arguments, ok => by simp only [resolveArguments, Except.ok.injEq] at ok; subst ok; simp [Arguments.any]
  | e :: rest, arguments, ok => by
    simp only [resolveArguments, exceptBind_eq_ok, exceptMapError_eq_ok] at ok
    obtain ⟨a, ha, tail, ht, ok⟩ := ok
    have ia := resolveOperand_below bounded dqs shapes misuse e a ha
    have it := resolveArguments_below bounded dqs shapes misuse (index + 1) rest tail ht
    cases ok
    simp_all [Arguments.any]

/-- For every scope that ends below a width, subquery shapes, base expression that reads below
the width (or none), operands and arguments: if resolution gives the arguments of {lit}`CASE`
({name}`resolveCase`), all of them read only columns below the width. A refused operand gives no
arguments and requires nothing. Proof sketch: induction over the operands; a comparison with the
base reads what its two sides read. -/
theorem resolveCase_below {width : Nat} {scope : Scope} (bounded : scope.Bounded width) (dqs : Bool)
    (shapes : SubqueryShapes) (misuse : Bool) (needsBase : Bool) (base : Option (Syntax.Expr × Operand))
    (index : Nat) (baseBelow : ∀ pair, base = some pair → pair.2.1.any (Expr.isColumnFrom width) = false) :
    (es : List Syntax.Expr) → ∀ arguments, resolveCase dqs scope shapes misuse needsBase base index es = .ok arguments →
      arguments.any (Expr.isColumnFrom width) = false
  | [], arguments, ok => by simp only [resolveCase, Except.ok.injEq] at ok; subst ok; simp [Arguments.any]
  | e :: rest, arguments, ok => by
    simp only [resolveCase, exceptBind_eq_ok, exceptMapError_eq_ok] at ok
    obtain ⟨r, hr, ok⟩ := ok
    have ir := resolveOperand_below bounded dqs shapes misuse e r hr
    split at ok
    · refine resolveCase_below bounded dqs shapes misuse false (some (e, r)) (index + 1) ?_ rest arguments ok
      intro pair same
      cases same
      exact ir
    · simp only [exceptBind_eq_ok] at ok
      obtain ⟨tail, ht, ok⟩ := ok
      have it := resolveCase_below bounded dqs shapes misuse false base (index + 1) baseBelow rest tail ht
      cases ok
      simp only [Arguments.any, Bool.or_eq_false_iff]
      refine ⟨?_, it⟩
      split
      · rename_i written value _
        have iv := baseBelow (written, value) rfl
        simp_all [Expr.any, Expr.isColumnFrom]
      · exact ir
end
