set_option doc.verso true

/-! The comparison and arithmetic operators of SQL, without their rules. The syntax and
the resolved forms name operators; the rules are in {lit}`Comparison` and
{lit}`Arithmetic`. Keeping the operators apart means a change of a rule does not
rebuild the syntax and the catalog. -/

namespace Belay.Sqlite.Model

/-- A comparison operator of SQL: the six that give NULL for a NULL operand, and
{lit}`IS` and {lit}`IS NOT`, which treat two NULLs as equal (R-24731-45773). -/
inductive Comparison where
  /-- {lit}`=` or {lit}`==`. -/
  | eq
  /-- {lit}`<>` or {lit}`!=`. -/
  | ne
  /-- {lit}`<`. -/
  | lt
  /-- {lit}`<=`. -/
  | le
  /-- {lit}`>`. -/
  | gt
  /-- {lit}`>=`. -/
  | ge
  /-- {lit}`IS`. -/
  | is
  /-- {lit}`IS NOT`. -/
  | isNot
  deriving Repr, DecidableEq

/-- An arithmetic operator of SQL. -/
inductive ArithmeticOperator where
  /-- {lit}`+`. -/
  | add
  /-- {lit}`-`. -/
  | subtract
  /-- {lit}`*`. -/
  | multiply
  /-- {lit}`/`. -/
  | divide
  /-- {lit}`%`. -/
  | remainder
  deriving Repr, DecidableEq

/-- The operator between two {lit}`SELECT` terms of a compound {lit}`SELECT` (ADR 0019, D3). All
four have the same precedence and apply from left to right. -/
inductive CompoundOperator where
  /-- {lit}`UNION ALL`: the left rows, then the right rows. -/
  | unionAll
  /-- {lit}`UNION`: the distinct rows of both sides. -/
  | union
  /-- {lit}`INTERSECT`: the distinct left rows that equal a right row. -/
  | intersect
  /-- {lit}`EXCEPT`: the distinct left rows that equal no right row. -/
  | except
  deriving Repr, DecidableEq

/-- The keywords of a compound operator, as SQLite writes them in its messages. -/
def CompoundOperator.keywords : CompoundOperator → String
  | .unionAll => "UNION ALL"
  | .union => "UNION"
  | .intersect => "INTERSECT"
  | .except => "EXCEPT"

end Belay.Sqlite.Model
