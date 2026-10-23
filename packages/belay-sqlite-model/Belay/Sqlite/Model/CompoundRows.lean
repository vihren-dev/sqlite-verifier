import Belay.Sqlite.Model.ExprFault

set_option doc.verso true

/-! The rows of a compound {lit}`SELECT` (ADR 0019, D3): the duplicate rule, which
{lit}`SELECT DISTINCT` shares, and each operator over the rows of its left operand and of its
right term. SQLite compares the rows of a compound without affinity, under the collation of each
compound column, and NULL equals NULL. -/

namespace Belay.Sqlite.Model.Resolved

/-- Whether two result rows compare equal under the collation of each column, as
{lit}`SELECT DISTINCT` and a compound {lit}`SELECT` compare them; NULL equals NULL. -/
def sameOutput (collations : List Collation) (first second : List Value) : Bool :=
  first.length == second.length && (collations.zip (first.zip second)).all fun (collation, a, b) =>
    collation.compare a b == .eq

/-- Whether every two rows that compare equal ({name}`sameOutput`) are the same values, so that
the row that SQLite keeps of a set of equal rows does not depend on its plan. -/
def equalRowsIdentical (collations : List Collation) (rows : List (List Value)) : Bool :=
  rows.all fun first => rows.all fun second => !sameOutput collations first second || first == second

/-- The first row of each set of equal rows ({name}`sameOutput`), in order. -/
def distinctRows (collations : List Collation) (rows : List (List Value)) : List (List Value) :=
  rows.foldl (fun kept row => if kept.any (sameOutput collations · row) then kept else kept ++ [row]) []

/-- The rows of an operator over the rows of its left operand and of its right term
({name}`CompoundOperator`): {lit}`UNION ALL` gives both lists; {lit}`UNION` the distinct rows of
both ({name}`distinctRows`); {lit}`INTERSECT` the distinct left rows that equal a right row; and
{lit}`EXCEPT` the distinct left rows that equal no right row. -/
def _root_.Belay.Sqlite.Model.CompoundOperator.combine (collations : List Collation) :
    CompoundOperator → List (List Value) → List (List Value) → List (List Value)
  | .unionAll, left, right => left ++ right
  | .union, left, right => distinctRows collations (left ++ right)
  | .intersect, left, right => (distinctRows collations left).filter fun row => right.any (sameOutput collations row)
  | .except, left, right => (distinctRows collations left).filter fun row => !right.any (sameOutput collations row)

/-- Whether the rows that an operator keeps are the same values in every plan of SQLite: always
for {lit}`UNION ALL`; for {lit}`UNION` when the equal rows of both sides are identical
({name}`equalRowsIdentical`); for {lit}`INTERSECT` and {lit}`EXCEPT`, which keep left rows
only, when the equal left rows are identical. -/
def _root_.Belay.Sqlite.Model.CompoundOperator.keepsCertain (collations : List Collation) :
    CompoundOperator → List (List Value) → List (List Value) → Bool
  | .unionAll, _, _ => true
  | .union, left, right => equalRowsIdentical collations (left ++ right)
  | .intersect, left, _ | .except, left, _ => equalRowsIdentical collations left

/-- The rows of the terms of a compound for an outer row, combined from left to right
({name}`CompoundOperator.combine`), and whether every operator keeps certain rows
({name}`CompoundOperator.keepsCertain`). Each term is subquery {lit}`index` of the context
({name}`EvalContext.subqueries`). -/
def Compound.combined (context : EvalContext) (compound : Compound) (outer : List Value) :
    List (List Value) × Bool :=
  compound.rest.foldl (fun (rows, certain) (operator, index) =>
      let right := (context.subqueries index outer).rows
      (operator.combine compound.collations rows right, certain && operator.keepsCertain compound.collations rows right))
    ((context.subqueries compound.first outer).rows, true)

/-- The result rows of a compound for an outer row, before its {lit}`ORDER BY` and its window
({name}`Compound.combined`). -/
def Compound.rows (context : EvalContext) (compound : Compound) (outer : List Value) : List (List Value) :=
  (compound.combined context outer).1

end Belay.Sqlite.Model.Resolved
