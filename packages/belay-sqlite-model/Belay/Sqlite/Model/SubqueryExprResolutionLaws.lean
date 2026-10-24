import Belay.Sqlite.Model.ExprResolutionLaws

set_option doc.verso true

/-! The resolution of the subquery forms of a condition (ADR 0017, S4): {lit}`EXISTS (q)`,
{lit}`x IN (q)` and a scalar subquery {lit}`(q)`, which name a subquery that resolution resolved before
({name}`Belay.Sqlite.Model.SubqueryShapes`). A statement without {lit}`FROM` and with one
subquery has the shapes of that one subquery, which these laws read. -/

namespace Belay.Sqlite.Model

variable {dqs : Bool} {scope : Scope} {shapes : SubqueryShapes} {misuse : Bool}

/-- {lit}`EXISTS (q)` resolves to the test of the subquery, without affinity, when the shapes know the
subquery. Proof sketch: the definition of the resolver. -/
theorem resolveOperand_exists {index : Nat} {shape : SubqueryShape} (found : shapes.find index = some shape) :
    resolveOperand dqs scope shapes misuse (.exists index) = .ok (.exists index, none) := by
  simp [resolveOperand, found]

/-- A scalar subquery resolves to its value, with the affinity of its result column, when the shapes know
the subquery as one with one result column. Proof sketch: the definition of the resolver, with
the shape of the subquery. -/
theorem resolveOperand_subquery {index : Nat} {shape : SubqueryShape} (found : shapes.column index = .ok shape) :
    resolveOperand dqs scope shapes misuse (.subquery index) = .ok (.subquery index, shape.affinity) := by
  simp [resolveOperand, found, Except.map]

/-- {lit}`x [NOT] IN (q)` resolves the operand and reads the one result column of the subquery
({name}`SubqueryShapes.column`); it compares under the affinity of the two
({name}`comparisonAffinity`) and the collation {name}`inCollation`, and has no affinity. The law is
an equation of the resolver, so {lit}`simp` rewrites the operand in place. Proof sketch: the definition of
the resolver. -/
theorem resolveOperand_inQuery (operand : Syntax.Expr) (index : Nat) (negated : Bool) :
    resolveOperand dqs scope shapes misuse (.inQuery operand index negated) = (do
      let a ← (resolveOperand dqs scope shapes misuse operand).mapError (·.under [0])
      let shape ← shapes.column index
      .ok (.inQuery a.1 index (comparisonAffinity a.2 shape.affinity) (inCollation scope operand shape) negated, none)) := by
  simp [resolveOperand]

/-- For a statement with one subquery whose shape has no parent, the only subquery is known to the
statement's own query: its shapes find index 0. Proof sketch: the base of the shapes of the statement's
query is 0, and the one shape is at position 0. -/
theorem SubqueryShapes.find_only {shape : SubqueryShape} (parentless : shape.parent = none) :
    ({ later := [shape] } : SubqueryShapes).find 0 = some shape := by
  simp [SubqueryShapes.find, SubqueryShapes.base, parentless]

/-- For a statement with one subquery whose shape has no parent, no derived column and one result
column, the shapes of the statement's query give that shape for the result column. Proof sketch:
{name}`SubqueryShapes.find_only` and the two tests of the column. -/
theorem SubqueryShapes.column_only {shape : SubqueryShape} (parentless : shape.parent = none)
    (plain : shape.derived = false) (one : shape.columns = 1) :
    ({ later := [shape] } : SubqueryShapes).column 0 = .ok shape := by
  simp [SubqueryShapes.column, SubqueryShapes.find_only parentless, plain, one]

end Belay.Sqlite.Model
