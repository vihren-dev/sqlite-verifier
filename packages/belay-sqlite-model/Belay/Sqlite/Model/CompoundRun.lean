import Belay.Sqlite.Model.QueryWindow
import Belay.Sqlite.Model.CompoundRows

set_option doc.verso true

/-! How SQLite ends the run of a compound {lit}`SELECT` (ADR 0019, D3; {lit}`multiSelect` and
{lit}`multiSelectOrderBy` of {lit}`select.c`). Without {lit}`ORDER BY`, SQLite runs the terms
from left to right into temporary tables, skips the right term of {lit}`EXCEPT` and
{lit}`INTERSECT` when the left rows are empty, reads {lit}`LIMIT` and {lit}`OFFSET` at the point
that the last operator gives, and gives the rows of a {lit}`UNION ALL` after it directly, until
the {lit}`LIMIT` is full. The model makes a failure certain only where SQLite runs it in each
plan and gives no row before it. -/

namespace Belay.Sqlite.Model.Resolved

/-- The window counters of a compound that gives its rows to the statement: the rows that
{lit}`OFFSET` still skips, the rows that {lit}`LIMIT` still allows (none for no limit), and the
number of rows given so far. -/
structure WindowCount where
  /-- The rows that {lit}`OFFSET` still skips. -/
  offset : Nat
  /-- The rows that {lit}`LIMIT` still allows, or none for no limit. -/
  limit : Option Nat
  /-- The rows given so far. -/
  given : Nat := 0

/-- The counters after a part of the compound gives {lit}`rows` rows: {lit}`OFFSET` skips first,
then {lit}`LIMIT` allows the rest up to its count. -/
def WindowCount.after (count : WindowCount) (rows : Nat) : WindowCount :=
  let skipped := min count.offset rows
  let given := match count.limit with
    | some limit => min limit (rows - skipped)
    | none => rows - skipped
  { offset := count.offset - skipped, limit := count.limit.map (· - given), given := count.given + given }

/-- The end of a term that SQLite runs into a temporary table: its own end, where a
{lit}`datatype mismatch`, which a term without a window does not have, is not described. -/
def RunEnd.intoTable : RunEnd → RunEnd
  | .done => .done
  | .may => .may
  | .function => .function
  | .overflow grouped => .overflow grouped
  | .mismatch => .may

/-- The end of a term that gives its rows directly to the statement, after the counters: a
certain failure stays certain only when no row came before it and no {lit}`OFFSET` skips the
term's row; an overflow of a query with {lit}`GROUP BY` may come after rows of its groups. -/
def RunEnd.direct (count : WindowCount) : RunEnd → RunEnd
  | .done => .done
  | .may => .may
  | .function => if count.given == 0 && count.offset == 0 then .function else .may
  | .overflow grouped => if count.given == 0 && !grouped then .overflow false else .may
  | .mismatch => .may

/-- The end of the terms of a {lit}`UNION ALL` chain that give their rows directly to the
statement, in order: SQLite does not run a term when the {lit}`LIMIT` is full, and stops at the
first term that does not end with {lean}`RunEnd.done`. -/
def directTerms (context : EvalContext) (outer : List Value) (count : WindowCount) : List Nat → RunEnd
  | [] => .done
  | index :: later =>
    if count.limit == some 0 then .done else
      let run := context.subqueries index outer
      match run.ending.direct count with
      | .done => directTerms context outer (count.after run.rows.length) later
      | .may => .may
      | .function => .function
      | .overflow grouped => .overflow grouped
      | .mismatch => .mismatch

/-- The rows and the end of an operand that SQLite runs into a temporary table, from the rows
and the end of its left part and the steps after it, in order: each step runs its term
({name}`RunEnd.intoTable`) unless a term before it did not end with {lean}`RunEnd.done`, or the
operator is {lit}`EXCEPT` or {lit}`INTERSECT` and the left rows are empty. -/
def fillSteps (context : EvalContext) (compound : Compound) (outer : List Value) :
    List (List Value) × RunEnd → List (CompoundOperator × Nat) → List (List Value) × RunEnd :=
  List.foldl fun (rows, ending) (operator, index) => match ending with
    | .done =>
      let run := context.subqueries index outer
      let skipped := match operator with
        | .except | .intersect => rows.isEmpty
        | .unionAll | .union => false
      if skipped then ([], .done) else (operator.combine compound.collations rows run.rows, run.ending.intoTable)
    | .may | .function | .overflow _ | .mismatch => (rows, ending)

/-- The end of a compound without {lit}`ORDER BY` whose last step before the {lit}`UNION ALL`
chain at its end has the operator and the right term {lit}`index`, after the steps before it in
reverse order: its left operand runs into a table ({name}`fillSteps`). For {lit}`UNION` and
{lit}`EXCEPT` the right term runs, and SQLite reads the window after it; for {lit}`INTERSECT`
SQLite reads the window first, and runs the right term only without {lit}`LIMIT 0`. SQLite skips
the right term of {lit}`EXCEPT` and {lit}`INTERSECT` when the left rows are empty. Then the
chain gives its rows ({name}`directTerms`). The window is none when a value of it is not an
integer. -/
def stepEnd (context : EvalContext) (compound : Compound) (outer : List Value) (window : Option WindowCount)
    (operator : CompoundOperator) (index : Nat) (earlier : List (CompoundOperator × Nat)) (chain : List Nat) : RunEnd :=
  let first := context.subqueries compound.first outer
  let (left, leftEnd) := fillSteps context compound outer (first.rows, first.ending.intoTable) earlier.reverse
  let right := context.subqueries index outer
  let rows := operator.combine compound.collations left right.rows
  let rightEnd := match operator with
    | .except | .intersect => if left.isEmpty then .done else right.ending.intoTable
    | .unionAll | .union => right.ending.intoTable
  let readFirst := match operator with
    | .intersect => true
    | .unionAll | .union | .except => false
  match leftEnd, window with
  | .done, none => if readFirst || rightEnd == .done then .mismatch else rightEnd
  | .done, some count =>
    if readFirst && count.limit == some 0 then .done
    else if rightEnd != .done then rightEnd
    else directTerms context outer (count.after rows.length) chain
  | .may, _ => .may
  | .function, _ => .function
  | .overflow grouped, _ => .overflow grouped
  | .mismatch, _ => .mismatch

/-- The end of a compound without {lit}`ORDER BY`, over its steps in reverse order and the terms
of the {lit}`UNION ALL` chain at its end: with no step left, SQLite reads the window before the
first term, and the first term starts the chain; a {lit}`UNION ALL` step joins the chain; any
other step is the last before the chain ({name}`stepEnd`). -/
def chainEnd (context : EvalContext) (compound : Compound) (outer : List Value) (window : Option WindowCount) :
    List (CompoundOperator × Nat) → List Nat → RunEnd
  | [], chain => match window with
    | none => .mismatch
    | some count => directTerms context outer count (compound.first :: chain)
  | (.unionAll, index) :: earlier, chain => chainEnd context compound outer window earlier (index :: chain)
  | (.union, index) :: earlier, chain => stepEnd context compound outer window .union index earlier chain
  | (.except, index) :: earlier, chain => stepEnd context compound outer window .except index earlier chain
  | (.intersect, index) :: earlier, chain => stepEnd context compound outer window .intersect index earlier chain

/-- How SQLite ends the run of a compound query for an outer row (ADR 0019, D3). With
{lit}`ORDER BY`, SQLite reads the window before the first term, runs nothing for
{lit}`LIMIT 0`, and merges the sorted terms, so that a term that does not end with
{lean}`RunEnd.done` makes the end {lean}`RunEnd.may`. Without {lit}`ORDER BY`, the order of
{name}`chainEnd`. A window value that is not an integer is {lean}`RunEnd.mismatch` at the point
where SQLite reads it. -/
def Compound.ending (context : EvalContext) (query : Query) (compound : Compound) (outer : List Value) : RunEnd :=
  let window := (query.bindWindow context.parameters).map fun bound => ({ offset := bound.offset, limit := bound.limit } : WindowCount)
  if query.orderBy.isEmpty then chainEnd context compound outer window compound.rest.reverse []
  else match window with
    | none => .mismatch
    | some count =>
      if count.limit == some 0 || compound.terms.all fun index => (context.subqueries index outer).ending == RunEnd.done then .done else .may

end Belay.Sqlite.Model.Resolved
