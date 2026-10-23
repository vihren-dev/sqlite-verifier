import Belay.Sqlite.Model.QueryEval
import Belay.Sqlite.Model.CompoundRows

set_option doc.verso true

/-! The result rows of a query over its source rows (ADR 0012, slice 1; ADR 0018, D3): the
records of its rows or groups, with the values of its aggregates for the expressions of each
group and {lit}`HAVING`; the rows of {lit}`SELECT DISTINCT`; then a stable sort by the
{lit}`ORDER BY` terms and the window. -/

namespace Belay.Sqlite.Model.Resolved

/-- The context of one group of an aggregate query: the values of the query's aggregates over
the group's rows ({name}`EvalContext.aggregates`), which its expressions name. -/
def Query.groupContext (context : EvalContext) (query : Query) (group : List (List Value)) : EvalContext :=
  { context with aggregates := query.aggregates.map (·.eval context group) }

/-- The result rows and sort values of a query, one per source row, or one per group of an
aggregate query for which {lit}`HAVING` is true. The expressions of a group read its first row
and the values of the query's aggregates over it ({name}`Query.groupContext`). -/
def records (context : EvalContext) (query : Query) (rows : List (List Value)) : List Record :=
  let sortValues := fun (context : EvalContext) (output : List Value) (source : List Value) =>
    query.orderBy.map fun term => match term.key with
      | .expression expression => expression.eval context source
      | .output index => output.getD index .null
  if query.aggregate then
    (queryGroups context query rows).filterMap fun group =>
      let inGroup := query.groupContext context group
      let source := group.headD []
      if query.having.all fun condition => truthy (condition.eval inGroup source) then
        let output := query.columns.map fun
          | .scalar expression => expression.eval inGroup source
          | .aggregate aggregate => aggregate.eval context group
        some (output, sortValues inGroup output source)
      else none
  else
    rows.map fun row =>
      let output := query.columns.map fun
        | .scalar expression => expression.eval context row
        | .aggregate aggregate => aggregate.eval context [row]
      (output, sortValues context output row)

/-- The records of {lit}`SELECT DISTINCT`: the first record of each set of records whose rows
compare equal ({name}`sameOutput`), in order. -/
def distinctRecords (collations : List Collation) (found : List Record) : List Record :=
  found.foldl (fun kept record => if kept.any (sameOutput collations ·.1 record.1) then kept else kept ++ [record]) []

/-- The records of a compound query for an outer row: each row of its terms
({name}`Compound.rows`) with the values of its {lit}`ORDER BY` terms, which name result columns.
An expression key, which resolution does not give a compound, reads the outer row. -/
def Query.compoundRecords (context : EvalContext) (query : Query) (compound : Compound) (outer : List Value) :
    List Record :=
  (compound.rows context outer).map fun row => (row, query.orderBy.map fun term => match term.key with
    | .output index => row.getD index .null
    | .expression expression => expression.eval context outer)

/-- The records of a query that its sort and window read: {name}`records` of the rows that
{lit}`WHERE` keeps, with only the first of equal rows for {lit}`SELECT DISTINCT`. The records of
a compound query are those of its terms for its one source row, the outer row
({name}`Query.compoundRecords`). -/
def Query.uniqueRecords (context : EvalContext) (query : Query) (rows : List (List Value)) : List Record :=
  match query.compound with
  | some compound => query.compoundRecords context compound (rows.headD [])
  | none =>
    let found := records context query (filtered context query rows)
    match query.distinct with
    | some collations => distinctRecords collations found
    | none => found

/-- Whether {lit}`SELECT DISTINCT` keeps the same rows in every order in which SQLite may read
them: the rows of each set of equal rows ({name}`sameOutput`) are the same values; always for a
query without {lit}`DISTINCT`. -/
def Query.distinctCertain (context : EvalContext) (query : Query) (rows : List (List Value)) : Bool :=
  match query.distinct with
  | none => true
  | some collations =>
    equalRowsIdentical collations ((records context query (filtered context query rows)).map Prod.fst)

/-- The result rows of a query over its source rows ({lit}`Query.source`): the records
({name}`Query.uniqueRecords`), a stable sort by the {lit}`ORDER BY` terms, then the window.
{lit}`Query.run` gives them with the fault of the query. -/
def Query.results (context : EvalContext) (query : Query) (rows : List (List Value)) : List (List Value) :=
  let directions := query.orderBy.map fun term => (term.descending, term.collation)
  let sorted := stableSort (fun a b => (compareSort directions a.2 b.2).isLE) (query.uniqueRecords context rows)
  let window := sorted.drop query.offset
  (match query.limit with | some limit => window.take limit | none => window).map Prod.fst

end Belay.Sqlite.Model.Resolved
