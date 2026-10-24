import Belay.Sqlite.Model.QueryEval

set_option doc.verso true

/-! The joins of a query (ADR 0012, amendments 2 and 3; ADR 0013, D5): the rows so far
joined with the rows of one more source. A joined row is the concatenation of the cells
of its sources. An inner join keeps the matching rows of the product; a left join adds
each unmatched left row with NULL in the columns of the source; a right join adds each row
of the source that no left row matches with NULL in the columns of the left input; a full
join adds both. -/

namespace Belay.Sqlite.Model.Resolved

/-- Whether the {lit}`ON` condition of the join is true for the joined row; a join
without a condition matches every row. -/
def QuerySource.matches (context : EvalContext) (join : QuerySource) (joined : List Value) : Bool :=
  join.condition.all fun condition => truthy (condition.eval context joined)

/-- The rows of a join for one left row: the concatenation with each row of the joined
source, in its order, for which the {lit}`ON` condition is true (R-44414-54710,
R-38465-03616). -/
def joinMatches (context : EvalContext) (row : List Value) (join : QuerySource) (candidates : List (List Value)) : List (List Value) :=
  candidates.filterMap fun cells =>
    let joined := row ++ cells
    if join.matches context joined then some joined else none

/-- The rows that one left row gives in a join with a source of {lit}`width` columns: its
{name}`joinMatches`; for a left or full join without a match, one row with NULL in every
column of the source (R-24610-05866). -/
def joinRow (context : EvalContext) (join : QuerySource) (width : Nat) (candidates : List (List Value)) (row : List Value) :
    List (List Value) :=
  match join.kind with
  | .inner | .right => joinMatches context row join candidates
  | .left | .full =>
    if (joinMatches context row join candidates).isEmpty then [row ++ List.replicate width .null]
    else joinMatches context row join candidates

/-- The rows of the joined source that no left row matches. -/
def unmatchedRight (context : EvalContext) (left : List (List Value)) (join : QuerySource) (candidates : List (List Value)) :
    List (List Value) :=
  candidates.filter fun cells => !left.any fun row => join.matches context (row ++ cells)

/-- The rows of a join of a table, whose rows are {lit}`candidates` with {lit}`width` cells,
after the rows so far, which have {lit}`leftWidth` cells: the rows of {name}`joinRow` for
each left row, in order; for a right or full join, then each row of {name}`unmatchedRight`
with NULL in the cells of the left input after the enclosing query's {lit}`outer` cells
(R-15753-04279, R-18902-30764). Use {lean}`([] : List Value)` outside a subquery. -/
def joinRows (context : EvalContext) (leftWidth : Nat) (left : List (List Value)) (join : QuerySource) (width : Nat)
    (candidates : List (List Value)) (outer : List Value := []) : List (List Value) :=
  left.flatMap (joinRow context join width candidates) ++ match join.kind with
    | .right | .full => (unmatchedRight context left join candidates).map
        ((outer ++ List.replicate (leftWidth - outer.length) .null) ++ ·)
    | .inner | .left => []

end Belay.Sqlite.Model.Resolved
