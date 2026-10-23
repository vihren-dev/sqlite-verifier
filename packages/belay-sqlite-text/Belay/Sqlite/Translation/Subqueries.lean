import Belay.Sqlite.Translation.Shapes

set_option doc.verso true

/-! Lift the subqueries of a statement into its list. The port of
{lit}`belay/sqlite/syntax_subqueries.py`: an expression names a subquery by its index in the
list, and each subquery names the query around it, none for the statement's query or write, else
the index of an earlier subquery. Outside a list, a subquery is refused with its range. -/

namespace Belay.Sqlite.Translation

open Belay.Sqlite.Model

/-- The clauses of a {lit}`select` production, which {lit}`Syntax.Subquery`,
{lit}`Syntax.Statement.select` and {lit}`Syntax.BodyStatement.select` share, each with its
ranges. A compound has no clauses of its own but its {lit}`ORDER BY`, {lit}`LIMIT` and
{lit}`OFFSET`, and its terms are subqueries. -/
structure Clauses where
  /-- The result columns. -/
  columns : Located (List Syntax.ResultColumn)
  /-- The first table of {lit}`FROM`, or none without {lit}`FROM`. -/
  source : Located (Option Syntax.TableReference)
  /-- The joins after the first table. -/
  joins : Located (List Syntax.Join)
  /-- The {lit}`WHERE` condition. -/
  filter : Located (Option Syntax.Expr)
  /-- The {lit}`GROUP BY` terms. -/
  groupBy : Located (List Syntax.Expr)
  /-- The {lit}`ORDER BY` terms. -/
  orderBy : Located (List Syntax.OrderTerm)
  /-- The {lit}`LIMIT` expression. -/
  limit : Located (Option Syntax.Expr)
  /-- The {lit}`OFFSET` expression. -/
  offset : Located (Option Syntax.Expr)
  /-- The {lit}`HAVING` condition. -/
  having : Located (Option Syntax.Expr)
  /-- Whether the query is {lit}`SELECT DISTINCT`. -/
  distinct : Located Bool
  /-- The terms of a compound, or none for one {lit}`SELECT`. -/
  compound : Located (Option Syntax.Compound)
  deriving Inhabited

/-- The ranges of the eight clauses before the {lit}`subqueries` or {lit}`parent` field, in the
order of the constructors' fields. -/
def Clauses.leading (clauses : Clauses) : Array Span :=
  #[clauses.columns.span, clauses.source.span, clauses.joins.span, clauses.filter.span, clauses.groupBy.span,
    clauses.orderBy.span, clauses.limit.span, clauses.offset.span]

/-- The clauses as a subquery, with the index of the query around it. -/
def Clauses.subquery (clauses : Clauses) (parent : Located (Option Nat)) (start stop : Nat) : Located Syntax.Subquery :=
  let value : Syntax.Subquery := {
    columns := clauses.columns.value
    source := clauses.source.value
    joins := clauses.joins.value
    filter := clauses.filter.value
    groupBy := clauses.groupBy.value
    orderBy := clauses.orderBy.value
    limit := clauses.limit.value
    offset := clauses.offset.value
    parent := parent.value
    having := clauses.having.value
    distinct := clauses.distinct.value
    compound := clauses.compound.value }
  composite value start stop
    (clauses.leading ++ #[parent.span, clauses.having.span, clauses.distinct.span, clauses.compound.span])

/-- The ranges of a {lit}`SELECT` constructor's fields: the clauses with the subqueries between
the eight leading clauses and {lit}`having`. -/
def Clauses.selectSpans (clauses : Clauses) (subqueries : Located (List Syntax.Subquery)) : Array Span :=
  clauses.leading ++ #[subqueries.span, clauses.having.span, clauses.distinct.span, clauses.compound.span]

/-- The mappers that the parts of a query call for their operands and nested queries; the
translation's root ties them to its own functions, as they call each other. -/
structure Mappers where
  /-- Map an {lit}`expr` production of a query. -/
  expression : SqlTree → ParseNode → TranslateM (Located Syntax.Expr)
  /-- Map a {lit}`select` production to its clauses. -/
  clauses : SqlTree → ParseNode → TranslateM Clauses

/-- Run the action with a new subquery list for one statement open, and give its subqueries;
the scope around it is kept. -/
def statementSubqueries (action : TranslateM α) : TranslateM (α × Array (Located Syntax.Subquery)) := do
  let around ← get
  set { around with active := some {} }
  let result ← action
  let items := match (← get).active with
    | some listed => listed.items.filterMap id
    | none => #[]
  set around
  return (result, items)

/-- Run the action with every subquery refused with the refusal, for a clause whose subqueries
the model does not place, such as RETURNING. -/
def noSubqueries (refusal : String) (action : TranslateM α) : TranslateM α := do
  let around ← get
  set { around with active := none, refusal }
  let result ← action
  set around
  return result

/-- Add a query of the node to the statement's list, with the clauses that the action maps, and
give its index and the other result of the action; its own subqueries and terms come after it.
Refuse it where no list is open. -/
def liftWith (select : ParseNode) (mapClauses : TranslateM (Clauses × β)) : TranslateM (Nat × β) := do
  let scope ← get
  let some listed := scope.active | unsupported select scope.refusal
  let index := listed.items.size
  let around := listed.current
  set { scope with active := some { items := listed.items.push none, current := some index } }
  let (clauses, other) ← mapClauses
  let scope ← get
  let items := (scope.active.map (·.items)).getD #[]
  let item := clauses.subquery (leaf around select.start select.stop) select.start select.stop
  set { scope with active := some { items := items.set! index (some item), current := around } }
  return (index, other)

/-- Add the subquery of a {lit}`select` production to the statement's list and give its index
({name}`liftWith`). -/
def lift (mappers : Mappers) (tree : SqlTree) (select : ParseNode) : TranslateM Nat :=
  (·.1) <$> liftWith select ((·, ()) <$> mappers.clauses tree select)

end Belay.Sqlite.Translation
