import Belay.Sqlite.Model
import Belay.Sqlite.Resolution.QueryForm
import Belay.Sqlite.Comparison
import Belay.Sqlite.Summation
import Belay.Sqlite.Json.JsonApply
import Belay.Sqlite.Date.Functions

set_option doc.verso true

/-! The Expressions and Queries levels of ADR 0012, slice 1 and amendments 2 and 3: the
value of an expression over one row, and the result rows of a query over its source
rows ({lit}`QueryJoins.lean` joins the tables into the source rows; a joined row is the
concatenation of the cells of its tables). The steps follow the ADR in order: the
{lit}`WHERE` filter, the groups, the result columns, a stable sort by the
{lit}`ORDER BY` terms, and the {lit}`OFFSET` and {lit}`LIMIT` window. -/

namespace Belay.Sqlite.Resolved

/-- Whether a value is true as a condition: a number that is not zero. -/
def truthy : Value → Bool
  | .integer value => value != 0
  | .real bits => (realScaled bits).any (· != 0)
  | .null | .text _ | .blob _ => false

/-- Whether a value is false as a condition: not NULL and not true. -/
def falsy (value : Value) : Bool := !value.isNull && !truthy value

mutual
/-- The value of an expression over the cells of one row, in column order. A column
past the end of the row reads as NULL. {lit}`AND` is false when an operand is false,
else NULL when an operand is NULL, else true; {lit}`OR` is the dual; {lit}`NOT`
keeps NULL. Arithmetic and {lit}`CAST` follow {name}`ArithmeticOperator.apply` and
{name}`castValue`; {lit}`COALESCE` gives its first operand unless that is NULL. A JSON
function gives the value of {name}`Json.apply` over the values of its arguments, and
NULL when it fails: whether and where SQLite reports that failure is
{lit}`Expr.mayFail` and {lit}`Expr.mustFail` of {lit}`JsonFaults`. A time keyword is NULL
here: the execution replaces it with the statement's clock text first
({lit}`Statement.atClock`). A date and time function gives the value of
{lit}`DateFunction.value` at its stored clock value. -/
def Expr.eval (row : List Value) : Expr → Value
  | .column position => row.getD position .null
  | .literal value => value
  | .compare operator left right => operator.apply (left.eval row) (right.eval row)
  | .and left right =>
    let (a, b) := (left.eval row, right.eval row)
    if falsy a || falsy b then truth false else if a.isNull || b.isNull then .null else truth true
  | .or left right =>
    let (a, b) := (left.eval row, right.eval row)
    if truthy a || truthy b then truth true else if a.isNull || b.isNull then .null else truth false
  | .not operand =>
    let value := operand.eval row
    if value.isNull then .null else truth (!truthy value)
  | .isNull operand negated => truth ((operand.eval row).isNull != negated)
  | .arithmetic operator left right => operator.apply (left.eval row) (right.eval row)
  | .cast affinity operand => castValue affinity (operand.eval row)
  | .coalesce first rest =>
    let value := first.eval row
    if value.isNullCell then rest.eval row else value
  | .json function arguments => match Json.apply function (arguments.eval row) with
    | .ok value => value
    | .error _ => .null
  | .date function arguments clock => function.value clock (arguments.eval row)
  | .arguments _ | .now _ => .null

/-- The values of the arguments of a call over one row, in written order. -/
def Arguments.eval (row : List Value) : Arguments → List Value
  | .nil => []
  | .cons head tail => head.eval row :: tail.eval row
end

/-- The first value of a list that no later value improves on, ignoring NULL; NULL
when every value is NULL. A tie keeps the earlier value, as SQLite's {lit}`min()` and
{lit}`max()` do. -/
def extremum (better : Value → Value → Bool) (values : List Value) : Value :=
  (values.filter (!·.isNull)).foldl (fun best value => if best.isNull || better value best then value else best) .null

/-- The value of an aggregate over the rows of one group. -/
def Aggregate.eval (rows : List (List Value)) : Aggregate → Value
  | .countRows => .integer rows.length
  | .count operand => .integer (rows.filter fun row => !(operand.eval row).isNull).length
  | .min operand => extremum (fun a b => compareValues a b == .lt) (rows.map operand.eval)
  | .max operand => extremum (fun a b => compareValues a b == .gt) (rows.map operand.eval)
  | .sum operand => ((sumOf (rows.map operand.eval)).sumValue).getD .null
  | .avg operand => (sumOf (rows.map operand.eval)).averageValue

/-- Whether an aggregate fails over the rows of one group: {lit}`SUM` with an integer
overflow that no later REAL input cleared. Every other aggregate never fails. -/
def Aggregate.fails (rows : List (List Value)) : Aggregate → Bool
  | .sum operand => ((sumOf (rows.map operand.eval)).sumValue).isNone
  | .countRows | .count _ | .min _ | .max _ | .avg _ => false

/-- The groups of rows by the values of the grouping terms, in the order in which
each group first appears. Two rows are in one group when each term's values compare
as equal. -/
def groups (terms : List Expr) (rows : List (List Value)) : List (List (List Value)) :=
  let key := fun row => terms.map (·.eval row)
  let same := fun first second => (List.zip (key first) (key second)).all fun (a, b) => compareValues a b == .eq
  (rows.foldl (fun found row => match found.findIdx? (fun group => group.head?.any (same row)) with
    | some index => found.modify index (· ++ [row])
    | none => found ++ [[row]]) [])

/-- One {lit}`ORDER BY` comparison: ascending, or descending when {lit}`descending`
is true. NULL is first in ascending order (R-12881-55998). -/
def compareTerm (descending : Bool) (a b : Value) : Ordering :=
  if descending then compareValues b a else compareValues a b

/-- The comparison of two lists of sort values, term by term, with one direction
per term; the first term that differs decides. A missing value reads as NULL. -/
def compareSort : List Bool → List Value → List Value → Ordering
  | [], _, _ => .eq
  | descending :: directions, a, b =>
    (compareTerm descending (a.headD .null) (b.headD .null)).then (compareSort directions a.tail b.tail)

/-- Insert an item into a list after every leading item that is at most the new
item by {lit}`le`. In a sorted list, the item goes after its equals, which keeps a
sort stable. -/
def insertStable (le : α → α → Bool) (item : α) : List α → List α
  | [] => [item]
  | head :: tail => if le head item then head :: insertStable le item tail else item :: head :: tail

/-- A stable sort by {lit}`le`: each item, in list order, is inserted after its
equals. Unlike {lit}`List.mergeSort`, it uses only structural recursion, so the
kernel can evaluate it in the proofs of conformance cases. -/
def stableSort (le : α → α → Bool) (items : List α) : List α :=
  items.foldl (fun sorted item => insertStable le item sorted) []

/-- A result row with its sort values. -/
abbrev Record := List Value × List Value

/-- The groups of an aggregate query: all rows as one group without {lit}`GROUP BY`,
also when there are none; else the groups of the grouping terms. -/
def queryGroups (query : Query) (rows : List (List Value)) : List (List (List Value)) :=
  if query.groupBy.isEmpty then [rows] else groups query.groupBy rows

/-- The result rows and sort values of a query, one per source row, or one per group
of an aggregate query. -/
def records (query : Query) (rows : List (List Value)) : List Record :=
  let sortValues := fun (output : List Value) (source : List Value) =>
    query.orderBy.map fun (key, _) => match key with
      | .expression expression => expression.eval source
      | .output index => output.getD index .null
  if query.aggregate then
    (queryGroups query rows).map fun group =>
      let output := query.columns.map fun
        | .scalar expression => expression.eval (group.headD [])
        | .aggregate aggregate => aggregate.eval group
      (output, sortValues output (group.headD []))
  else
    rows.map fun row =>
      let output := query.columns.map fun
        | .scalar expression => expression.eval row
        | .aggregate aggregate => aggregate.eval [row]
      (output, sortValues output row)

/-- The rows of the table in rowid order, as the source of a query. -/
def sourceRows (table : Table) : List (List Value) :=
  (stableSort (fun a b => decide (a.rowid ≤ b.rowid)) table.rows).map Row.values

/-- The rows that the {lit}`WHERE` condition keeps: those where it is true. -/
def filtered (query : Query) (rows : List (List Value)) : List (List Value) :=
  rows.filter fun row => query.filter.all fun condition => truthy (condition.eval row)

/-- The result rows of a query over its source rows ({lit}`Query.source`): filter,
groups and columns, a stable sort by the {lit}`ORDER BY` terms, then the window. -/
def Query.run (query : Query) (rows : List (List Value)) : List (List Value) :=
  let directions := query.orderBy.map Prod.snd
  let sorted := stableSort (fun a b => (compareSort directions a.2 b.2).isLE)
    (records query (filtered query rows))
  let window := sorted.drop query.offset
  (match query.limit with | some limit => window.take limit | none => window).map Prod.fst

/-- Whether a query fails over its source rows, so that SQLite stops the statement with the
{lit}`integer overflow` error: an aggregate query without {lit}`LIMIT 0` in which an
aggregate of a result column fails ({name}`Aggregate.fails`) for some group. With
{lit}`LIMIT 0`, SQLite skips the evaluation and returns no rows. -/
def Query.fails (query : Query) (rows : List (List Value)) : Bool :=
  query.aggregate && query.limit != some 0 && (queryGroups query (filtered query rows)).any fun group =>
    query.columns.any fun
      | .aggregate aggregate => aggregate.fails group
      | .scalar _ => false

end Belay.Sqlite.Resolved
