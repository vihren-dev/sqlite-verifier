import Belay.Sqlite.Model.QueryRun
import Belay.Sqlite.Model.QueryFunctions

set_option doc.verso true

/-! The subqueries of a statement (ADR 0018, D1): the run of one subquery for an outer row,
and the evaluation context of a statement whose expressions name its subqueries by index.
A subquery's row is the outer row followed by the subquery's own cells, so its sources are
joined after the outer row, and a correlated reference is a cell position. -/

namespace Belay.Sqlite.Model.Resolved

/-- The source rows of a subquery for an outer row: its sources joined in written order
({name}`QuerySource.join`) from the outer row, so each row starts with the outer cells; none
when a table is missing. An outer row with fewer cells than {name}`Query.outer`, such as the
row without cells over which the model evaluates a constant term, is filled with NULL, so the
subquery's own cells keep their positions. With no outer cells this is {name}`Query.source`. -/
def Query.sourceAfter (context : EvalContext) (outer : List Value) (query : Query) (database : Database) :
    Option SourceRows :=
  let cells := outer ++ List.replicate (query.outer - outer.length) .null
  query.sources.foldlM (QuerySource.join context database) { rows := [cells], width := cells.length, fault := .none }

/-- Whether SQLite gives the same first values on both sides of a cut before {lit}`position` of
the sorted records, in every order that the {lit}`ORDER BY` terms allow: the cut is at the start
or after the end, or the records around it are not tied, or every record tied with the one
after the cut has the same first value. -/
def certainCut (directions : List (Bool × Collation)) (sorted : List Record) (position : Nat) : Bool :=
  match position, sorted[position]? with
  | 0, _ | _, none => true
  | before + 1, some after =>
    match sorted[before]? with
    | none => true
    | some previous =>
      compareSort directions previous.2 after.2 != .eq ||
        (sorted.filter (compareSort directions ·.2 after.2 == .eq)).all (·.1.head? == after.1.head?)

/-- Whether the first values of a subquery's window are the same in every order that its
{lit}`ORDER BY` terms allow, for a window of at most {lit}`limit` rows after its
{lit}`OFFSET`: no rows, or both cuts of the window are certain ({name}`certainCut`). Without
{lit}`ORDER BY` every record is tied, as SQLite may read the rows in any order. -/
def Query.windowCertain (context : EvalContext) (query : Query) (rows : List (List Value)) (limit : Option Nat) :
    Bool :=
  limit == some 0 ||
    let directions := query.orderBy.map fun term => (term.descending, term.collation)
    let sorted := stableSort (fun a b => (compareSort directions a.2 b.2).isLE)
      (query.uniqueRecords context rows)
    certainCut directions sorted query.offset && limit.all (certainCut directions sorted <| query.offset + ·)

/-- The run of a subquery for an outer row: the rows of {name}`Query.run` over its source rows
({name}`Query.sourceAfter`), with the fault of the sources and of the run softened to
{lean}`Fault.may`, because SQLite evaluates a subquery only when it needs its value. A missing
table, an integer overflow and a value of its window that is not an integer
({name}`Query.bindWindow`), which the model does not describe inside a subquery, are
{lean}`Fault.may` too; the window is bound to the values of the context when the subquery
runs. Its first row is certain when the window of one row is ({name}`Query.windowCertain`),
and its rows when its own window is. Its end ({name}`RunEnd`) keeps the failure of the run
without the softening, for a compound that reads it for its terms. -/
def Query.subqueryRun (context : EvalContext) (database : Database) (outer : List Value) (query : Query) :
    SubqueryRun :=
  match query.sourceAfter context outer database with
  | none => { rows := [], fault := .may, ending := .may }
  | some source => match query.bindWindow context.parameters with
    | none => { rows := [], fault := .may, ending := .mismatch }
    | some bound =>
      let run := bound.run context source.rows
      { rows := run.rows, fault := if run.overflow then .may else (source.fault.join run.fault).soften,
        firstCertain := bound.windowCertain context source.rows (some (min 1 (bound.limit.getD 1))),
        rowsCertain := bound.windowCertain context source.rows bound.limit,
        ending := if run.mismatch then .mismatch else if run.overflow then .overflow !bound.groupBy.isEmpty
          else match source.fault.join run.fault with
            | .none => .done
            | .may => .may
            | .must => .function }

/-- The context of a statement's subqueries at a nesting depth, with the statement's clock value,
the counters of its connection and the values bound to its parameters at every depth: with no depth left, the plain context
with the values; else subquery {lit}`index` runs ({name}`Query.subqueryRun`) in the context one
depth below, which serves the subqueries that its own expressions name, all later in the list. -/
def subqueryContext (clock : Int) (counters : Counters) (parameters : List Value) (database : Database) (subqueries : List Query) :
    Nat → EvalContext
  | 0 => { EvalContext.plain clock with parameters, counters }
  | depth + 1 =>
    { clock, parameters, counters, subqueries := fun index outer => match subqueries[index]? with
        | some query => query.subqueryRun (subqueryContext clock counters parameters database subqueries depth) database outer
        | none => { rows := [], fault := .none } }

/-- The evaluation context of a statement at a clock value, with the counters of its connection
and the values bound to its parameters, over a database: its subqueries at the depth of their number
({name}`subqueryContext`), which bounds their nesting because each subquery's expressions name
only later ones. Without subqueries it is the plain context with the counters and the values. Use {lean}`([] : List Value)` for
the values of a statement that binds none, such as a trigger body. -/
def statementContext (clock : Int) (counters : Counters) (parameters : List Value) (database : Database) (subqueries : List Query) :
    EvalContext :=
  subqueryContext clock counters parameters database subqueries subqueries.length

/-- For every clock value, counters, list of values and database, the context of a statement without
subqueries is the plain context of the clock value with the counters and the values as its parameters. Proof
sketch: an empty list gives depth 0, and {name}`subqueryContext` at depth 0 is that context by
definition. -/
@[simp] theorem statementContext_nil (clock : Int) (counters : Counters) (parameters : List Value) (database : Database) :
    statementContext clock counters parameters database [] = { EvalContext.plain clock with parameters, counters } := rfl

end Belay.Sqlite.Model.Resolved
