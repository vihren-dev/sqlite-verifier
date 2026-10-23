import Belay.Sqlite.Model.Resolution.ResolvedExprForm
import Belay.Sqlite.Model.Resolution.PragmaSource

set_option doc.verso true

/-! The resolved form of a single-table query of ADR 0012, slice 1: what
{lit}`resolve` gives for a {lit}`SELECT` and what the Queries level evaluates: its
sources with their joins, and its parts over the values of {lit}`ResolvedExprForm.lean`.
Names are already table positions, and the affinity rules of a comparison are
already applied to its literal operands, so evaluation needs no catalog. -/

namespace Belay.Sqlite.Model.Resolved

/-- The kind of a resolved join: inner, or left, right or full outer. -/
inductive JoinKind where
  /-- An inner join: the rows of the product for which the condition is true. -/
  | inner
  /-- A left outer join: the inner join, and each left row that no right row matches,
  with NULL in every right column. -/
  | left
  /-- A right outer join: the inner join, and each right row that no row of the left
  input matches, with NULL in every column of the left input. -/
  | right
  /-- A full outer join: the inner join and the added rows of both a left and a right
  join. -/
  | full
  deriving Repr, DecidableEq

/-- A source of a {lit}`FROM` clause (ADR 0013, D5): a table, a {lit}`json_each(json [, path])`
call whose arguments read the joined row before it, a subquery, or the rows of a pragma
(ADR 0019, D2). -/
inductive Source where
  /-- The table at the catalog position, with its rows in rowid order. -/
  | table (position : Nat)
  /-- {lit}`json_each` with its JSON argument and optional path, over the row before it
  (ADR 0012, amendment 5, slice 6d). -/
  | each (json : Expr) (path : Option Expr)
  /-- A subquery. Resolution does not give it yet (ADR 0013, amendment 2); its payload
  comes with the subquery ADR, and execution treats it as unmodeled. -/
  | subquery
  /-- The rows of a pragma ({name}`PragmaRows`), as {lit}`PRAGMA table_info(t)` or
  {lit}`pragma_table_info('t')` gives them. -/
  | pragma (rows : PragmaRows)
  deriving Repr, DecidableEq

/-- Whether the source is {lit}`json_each`. -/
def Source.isEach : Source → Bool
  | .each .. => true
  | .table _ | .subquery | .pragma _ => false

/-- One source of {lit}`FROM` in written order: how it joins the row so far, the source,
and its {lit}`ON` condition over the row so far and its cells; {lean}`(none : Option Expr)`
for no condition. The first source is an inner join without a condition. -/
structure QuerySource where
  /-- The kind of the join with the sources before it. -/
  kind : JoinKind
  /-- The source. -/
  source : Source
  /-- The {lit}`ON` condition, over the cells of the sources up to this one. -/
  condition : Option Expr
  deriving Repr, DecidableEq

/-- The first source of a {lit}`FROM`: the table at the catalog position, as an inner join
without a condition. -/
def QuerySource.first (position : Nat) : QuerySource := { kind := .inner, source := .table position, condition := none }

/-- The terms of a resolved compound {lit}`SELECT` (ADR 0019, D3), each a query of the
statement's list of subqueries by its index: the left-most term, each operator with the term on
its right from left to right, and the collation of each result column. Two rows are equal when
each column compares equal under its collation, NULL equal to NULL; the collation of a column is
that of the left-most term whose expression has one, {lit}`BINARY` when none has one. -/
structure Compound where
  /-- The index of the left-most term. -/
  first : Nat
  /-- Each operator with the index of the term on its right, from left to right. -/
  rest : List (CompoundOperator × Nat)
  /-- The collation of each result column. -/
  collations : List Collation
  deriving Repr, DecidableEq

/-- The indexes of the terms of a compound, from left to right. -/
def Compound.terms (compound : Compound) : List Nat :=
  compound.first :: compound.rest.map (·.2)

/-- A resolved {lit}`SELECT`: its sources, the {lit}`WHERE` condition, whether it is an
aggregate query with its grouping terms, the result columns with their names, the
{lit}`ORDER BY` terms with a flag for {lit}`DESC`, and the window: literal values, or the
numbers of the parameters that give them when the query runs. Use
{lean}`(none : Option Nat)` for no {lit}`LIMIT`. -/
structure Query where
  /-- The sources of {lit}`FROM` in written order; empty for a {lit}`SELECT` without
  {lit}`FROM`, whose source is one row with no columns. An expression names a cell by its
  position in the concatenated row of all sources. -/
  sources : List QuerySource
  /-- The {lit}`WHERE` condition, or {lean}`(none : Option Expr)` for every row. -/
  filter : Option Expr
  /-- Whether the query is an aggregate query: it has {lit}`GROUP BY` or an aggregate. -/
  aggregate : Bool
  /-- The {lit}`GROUP BY` terms, each with the collation that decides when two values are one
  group; empty for one group of all rows. -/
  groupBy : List (Expr × Collation)
  /-- The result columns, in order. -/
  columns : List Output
  /-- The name of each result column. -/
  names : List String
  /-- The {lit}`ORDER BY` terms. -/
  orderBy : List SortTerm
  /-- The number of rows that a literal {lit}`OFFSET` skips; zero without {lit}`OFFSET` and
  with {lit}`OFFSET ?`. -/
  offset : Nat
  /-- The literal {lit}`LIMIT`, or {lean}`(none : Option Nat)` for no limit and with
  {lit}`LIMIT ?`. -/
  limit : Option Nat
  /-- The number of the parameter of {lit}`LIMIT ?`, or {lean}`(none : Option Nat)` for a literal
  or no {lit}`LIMIT`. When the query runs, the value bound to the parameter replaces
  the literal {lit}`limit` ({lit}`Query.bindWindow`). -/
  limitParameter : Option Nat := none
  /-- The number of the parameter of {lit}`OFFSET ?`, or {lean}`(none : Option Nat)` for a
  literal or no {lit}`OFFSET`. When the query runs, the value bound to the parameter replaces
  the literal {lit}`offset` ({lit}`Query.bindWindow`). -/
  offsetParameter : Option Nat := none
  /-- The number of cells of the row of the queries around a subquery, which come before its
  own cells (ADR 0018, D1); {lean}`0` for the query of a statement. -/
  outer : Nat := 0
  /-- The aggregates that the query's expressions name by index ({lit}`Expr.aggregateValue`),
  computed over each group (ADR 0018, D3); empty when no expression names one. -/
  aggregates : List Aggregate := []
  /-- The {lit}`HAVING` condition over each group, or {lean}`(none : Option Expr)` without it. -/
  having : Option Expr := none
  /-- The collation of each result column of {lit}`SELECT DISTINCT`, under which equal rows are
  one row; {lean}`(none : Option (List Collation))` without {lit}`DISTINCT`. -/
  distinct : Option (List Collation) := none
  /-- The terms of a compound {lit}`SELECT` ({name}`Compound`), or
  {lean}`(none : Option Compound)` for one {lit}`SELECT`. A compound query has no sources, no
  filter and no columns of its own; its rows are those of its terms, its names those of the
  left-most term, and its {lit}`ORDER BY` terms name result columns. -/
  compound : Option Compound := none
  deriving Repr, DecidableEq

end Belay.Sqlite.Model.Resolved
