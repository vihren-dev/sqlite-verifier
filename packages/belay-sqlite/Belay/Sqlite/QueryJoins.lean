import Belay.Sqlite.QueryEval

set_option doc.verso true

/-! The source rows of a query (ADR 0012, amendments 2 and 3): the rows of the first
table in rowid order, joined left to right with the table of each join. A joined row is
the concatenation of the cells of its tables. An inner join keeps the matching rows of
the product; a left join adds each unmatched left row with NULL in the right columns; a
right join adds each right row that no left row matches with NULL in the columns of the
left input; a full join adds both. -/

namespace Belay.Sqlite.Resolved

/-- Whether the {lit}`ON` condition of the join is true for the joined row; a join
without a condition matches every row. -/
def Join.matches (join : Join) (joined : List Value) : Bool :=
  join.condition.all fun condition => truthy (condition.eval joined)

/-- The rows of a join for one left row: the concatenation with each row of the joined
table in rowid order for which the {lit}`ON` condition is true (R-44414-54710,
R-38465-03616). -/
def joinMatches (row : List Value) (join : Join) (table : Table) : List (List Value) :=
  (sourceRows table).filterMap fun cells =>
    let joined := row ++ cells
    if join.matches joined then some joined else none

/-- The rows that one left row gives in a join: its {name}`joinMatches`; for a left or
full join without a match, one row with NULL in every column of the joined table
(R-24610-05866). -/
def joinRow (join : Join) (table : Table) (row : List Value) : List (List Value) :=
  match join.kind with
  | .inner | .right => joinMatches row join table
  | .left | .full =>
    if (joinMatches row join table).isEmpty then [row ++ List.replicate table.shape.columns.length .null]
    else joinMatches row join table

/-- The rows of the joined table, in rowid order, that no left row matches. -/
def unmatchedRight (left : List (List Value)) (join : Join) (table : Table) : List (List Value) :=
  (sourceRows table).filter fun cells => !left.any fun row => join.matches (row ++ cells)

/-- The rows of a join after the rows so far, whose rows have {lit}`width` cells: the
rows of {name}`joinRow` for each left row, in order; for a right or full join, then each
row of {name}`unmatchedRight` with NULL in the {lit}`width` cells of the left input
(R-15753-04279, R-18902-30764). -/
def joinRows (width : Nat) (left : List (List Value)) (join : Join) (table : Table) : List (List Value) :=
  left.flatMap (joinRow join table) ++ match join.kind with
    | .right | .full => (unmatchedRight left join table).map (List.replicate width .null ++ ·)
    | .inner | .left => []

/-- The rows of the tables of a query over a database: the rows of the first table in rowid
order, joined with each join's table in order ({name}`joinRows`), with the width of the
tables so far; none when a table is missing. A query of one table has the rows of
{name}`sourceRows`, and a query without a table one row with no cells. The
{lit}`json_each` sources join these rows ({lit}`Query.source`). -/
def Query.tableSource (query : Query) (database : Database) : Option (List (List Value)) := do
  let some table := query.table | pure [[]]
  let first ← database table
  let (rows, _) ← query.joins.foldlM (fun (rows, width) join => (database join.table).map fun table =>
    (joinRows width rows join table, width + table.shape.columns.length)) (sourceRows first, first.shape.columns.length)
  pure rows

end Belay.Sqlite.Resolved
