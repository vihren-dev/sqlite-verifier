import Belay.Sqlite.Model.ResolveTermsBelow
import Belay.Sqlite.Model.Resolution.IndexTerms

set_option doc.verso true

/-! The CHECK lemma for CREATE INDEX (ADR 0022, D3, slice 4): the key terms and the filter that
resolution gives for an index read only columns of the table, which is what
{lit}`CatalogIndex.supported` requires. "Reads below the width" means that {lit}`Expr.any` of
{lit}`Expr.isColumnFrom` for the width is false. -/

namespace Belay.Sqlite.Model

open Resolved

/-- For the given width and key term: a column term is at a position below the width, and an
expression term reads below the width. This is what {name}`CatalogIndex.supported` requires of each
term. -/
def KeyTerm.Below (width : Nat) : KeyTerm → Prop
  | .column position => position < width
  | .expression value => value.any (Expr.isColumnFrom width) = false

/-- For every scope that ends below a width and expression: if the expression resolves to the key
term ({name}`indexExpressionTerm`), the term reads below the width. A refused term requires
nothing. Proof sketch: an accepted term wraps the resolved operand, which
{name}`resolveOperand_below` bounds. -/
theorem indexExpressionTerm_below {width : Nat} {scope : Scope} (bounded : scope.Bounded width) {dqs : Bool}
    {expression : Syntax.Expr} {term : KeyTerm}
    (ok : indexExpressionTerm dqs scope expression = .ok term) : term.Below width := by
  simp only [indexExpressionTerm, exceptBind_eq_ok] at ok
  obtain ⟨_, _, ok⟩ := ok
  split at ok
  · cases ok
  · simp only [exceptBind_eq_ok] at ok
    obtain ⟨_, _, ⟨resolved, affinity⟩, ho, ok⟩ := ok
    have := resolveOperand_below bounded dqs {} true expression _ ho
    split at ok
    · cases ok
    · cases ok; exact this

/-- For every scope that ends below the number of columns, columns, expression of the syntax and
key term: if the expression resolves to the term ({name}`indexTerm`), the term is below the number
of columns. A refused term requires nothing. Proof sketch: a column term is a position that
{name}`columnPosition_lt` bounds; a {lit}`COLLATE` keeps the term of its operand; any other form is
{name}`indexExpressionTerm_below`. -/
theorem indexTerm_below {dqs : Bool} {scope : Scope} {columns : List CatalogColumn}
    (bounded : scope.Bounded columns.length) :
    (expression : Syntax.Expr) → ∀ term, indexTerm dqs scope columns expression = .ok term →
      term.Below columns.length
  | .collate operand name, term, ok => by
    simp only [indexTerm, exceptBind_eq_ok] at ok
    obtain ⟨inner, hi, ok⟩ := ok
    have := indexTerm_below bounded operand inner hi
    split at ok <;> cases ok <;> exact this
  | .identifier name quote, term, ok => by
    simp only [indexTerm] at ok
    cases found : columnPosition columns name with
    | some position => simp only [found, Except.ok.injEq] at ok; subst ok; exact columnPosition_lt found
    | none =>
      simp only [found] at ok
      split at ok
      · exact indexExpressionTerm_below bounded ok
      · split at ok <;> cases ok
  | .string _, term, ok => by cases ok
  | expression@.null, term, ok | expression@(.numeric _), term, ok | expression@(.blob _), term, ok
  | expression@(.parameter _), term, ok | expression@(.currentTime _), term, ok
  | expression@(.qualified ..), term, ok | expression@(.negate _), term, ok | expression@(.positive _), term, ok
  | expression@(.compare ..), term, ok | expression@(.and ..), term, ok | expression@(.or ..), term, ok
  | expression@(.not _), term, ok | expression@(.isNull ..), term, ok | expression@(.callStar _), term, ok
  | expression@(.call ..), term, ok | expression@(.arithmetic ..), term, ok | expression@(.cast ..), term, ok
  | expression@(.exists _), term, ok | expression@(.inQuery ..), term, ok | expression@(.subquery _), term, ok
  | expression@(.inList ..), term, ok | expression@(.between ..), term, ok | expression@(.caseOf ..), term, ok
  | expression@(.concatenate ..), term, ok | expression@(.raise ..), term, ok => by
    simp only [indexTerm] at ok
    exact indexExpressionTerm_below bounded ok

/-- For every scope that ends below the number of columns, columns, terms and keys: if the terms
resolve to the keys ({name}`indexKeys`), the term of each key is below the number of columns. A
refused term requires nothing. -/
theorem indexKeys_below {dqs : Bool} {scope : Scope} {columns : List CatalogColumn}
    (bounded : scope.Bounded columns.length) {terms : List Syntax.OrderTerm} {keys : List IndexKey}
    (ok : indexKeys dqs scope columns terms = .ok keys) : ∀ key ∈ keys, key.term.Below columns.length := by
  intro key member
  unfold indexKeys at ok
  split at ok
  · cases ok
  obtain ⟨⟨term, item⟩, _, hf⟩ := mapM_ok_mem _ ok key member
  simp only [exceptMapError_eq_ok, exceptFmap_eq_ok] at hf
  obtain ⟨found, hk, rfl⟩ := hf
  exact indexTerm_below bounded _ found hk

/-- For every scope that ends below a width and filter: if the filter of an index resolves to an
expression ({name}`indexFilter`), the expression reads below the width. A filter that is missing
or refused requires nothing. -/
theorem indexFilter_below {width : Nat} {dqs : Bool} {scope : Scope} (bounded : scope.Bounded width)
    {filter : Option Syntax.Expr} {resolved : Resolved.Expr}
    (ok : indexFilter dqs scope filter = .ok (some resolved)) : resolved.any (Expr.isColumnFrom width) = false := by
  cases filter with
  | none => cases ok
  | some term =>
    simp only [indexFilter, exceptBind_eq_ok, condition_eq_ok] at ok
    obtain ⟨_, _, _, _, found, ⟨operand, ho, rfl⟩, ok⟩ := ok
    have := resolveOperand_below bounded dqs {} true term operand ho
    split at ok
    · cases ok
    · simp only [Except.ok.injEq, Option.some.injEq] at ok; subst ok; exact this

end Belay.Sqlite.Model
