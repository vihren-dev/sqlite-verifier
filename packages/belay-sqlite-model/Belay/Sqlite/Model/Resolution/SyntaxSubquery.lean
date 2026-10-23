import Belay.Sqlite.Model.Resolution.SyntaxExpr

set_option doc.verso true

/-! Subqueries and compound {lit}`SELECT` terms as written (ADR 0018, D1; ADR 0019, D3). A
statement lists its subqueries in the order of their text, and an expression or a compound names
a subquery by its index in that list. -/

namespace Belay.Sqlite.Model.Syntax

/-- The terms of a compound {lit}`SELECT` as written (ADR 0019, D3): the left-most term, then each
operator with the term on its right, in written order. Each term is a {lit}`SELECT` of the
statement's list of subqueries, named by its index; its parent is the query that holds the
compound. For example, {lit}`SELECT 1 UNION SELECT 2` lists the two terms as subqueries 0 and 1,
and its terms are {lean}`({ first := 0, rest := [(.union, 1)] } : Compound)`. -/
structure Compound where
  /-- The index of the left-most term. -/
  first : Nat
  /-- Each operator with the index of the term on its right, from left to right. -/
  rest : List (CompoundOperator × Nat)
  deriving Repr, BEq, DecidableEq

/-- A subquery of a statement as written (ADR 0018, D1): its clauses, as those of
{lit}`Syntax.Statement.select`, and the query around it, an earlier subquery by its index in
the statement's list or {lean}`(none : Option Nat)` for the statement's query. The frontend
lists the subqueries in the order of their text, so a subquery comes after the query around
it; an expression names a subquery by its index ({lit}`Expr.exists`, {lit}`Expr.inQuery`,
{lit}`Expr.subquery`). A compound subquery has no columns and no {lit}`FROM`, and its
{lit}`compound` names its terms, whose parent is the compound subquery; its {lit}`ORDER BY`,
{lit}`LIMIT` and {lit}`OFFSET` are those of the compound. -/
structure Subquery where
  /-- The result columns. -/
  columns : List ResultColumn
  /-- The first table of {lit}`FROM`, or none without {lit}`FROM`. -/
  source : Option TableReference
  /-- The joins after the first table, in order. -/
  joins : List Join
  /-- The {lit}`WHERE` condition. -/
  filter : Option Expr
  /-- The {lit}`GROUP BY` terms. -/
  groupBy : List Expr
  /-- The {lit}`ORDER BY` terms. -/
  orderBy : List OrderTerm
  /-- The {lit}`LIMIT` expression. -/
  limit : Option Expr
  /-- The {lit}`OFFSET` expression. -/
  offset : Option Expr
  /-- The index of the subquery around this one, or none for the statement's query. -/
  parent : Option Nat
  /-- The {lit}`HAVING` condition (ADR 0018, D3). -/
  having : Option Expr := none
  /-- Whether the query is {lit}`SELECT DISTINCT`. -/
  distinct : Bool := false
  /-- The terms of a compound subquery ({name}`Compound`), or {lean}`(none : Option Compound)`
  for one {lit}`SELECT`. -/
  compound : Option Compound := none
  deriving Repr, BEq

end Belay.Sqlite.Model.Syntax
