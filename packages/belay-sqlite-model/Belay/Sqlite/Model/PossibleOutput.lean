import Belay.Sqlite.Model.StatementOutput
import Belay.Sqlite.Model.PossibleResults

set_option doc.verso true

/-! The results that SQLite may give for a statement that runs (ADR 0018, D6): for a query, one
result for each order that SQLite may use, with each tie group in normal form. The conformance
harness checks that SQLite's rows are one of them, and the user surface shows them as one output
(ADR 0017, D3). -/

namespace Belay.Sqlite.Model

/-- The results that SQLite may give for a statement with the values bound to its parameters,
for a query that succeeds
({name}`Resolved.Query.possibleOn`); none for every other statement and for a query that fails. -/
def possibleOutput (clock : Int) (parameters : List Value) (statement : Resolved.Statement) (before : SqlState)
    (transition : SqlTransition) : Option (List (List ResultRow)) :=
  match statement, transition with
  | .query query subqueries, .next _ =>
    query.possibleOn clock (before.counters.view statement.counterReads) parameters before.database subqueries
  | .query .., .halt _ => none
  | .createTable .., _ | .createIndex .., _ | .createTrigger .., _ | .addColumn .., _ | .drop .., _ | .begin, _
  | .commit, _ | .rollback, _ | .insert .., _ | .upsert .., _ | .update .., _ | .delete .., _ | .prepareError _, _
  | .setting .., _ => none

end Belay.Sqlite.Model
