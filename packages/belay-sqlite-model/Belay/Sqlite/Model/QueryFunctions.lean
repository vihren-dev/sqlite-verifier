import Belay.Sqlite.Model.QueryJoins
import Belay.Sqlite.Model.Json.Each
import Belay.Sqlite.Model.PragmaRun

set_option doc.verso true

/-! The source rows of a query (ADR 0013, D5): its sources joined in written order, as
SQLite's nested loop does, from the one row with no cells. A table gives its rows in rowid
order; {lit}`json_each` gives its rows over the values of its arguments on each row so far
(ADR 0012, amendment 5, slice 6d). A {lit}`json_each` call that fails gives no rows here,
and makes the fault of the source {lit}`may`: SQLite reports it when it scans the
source, so the supported-subset check refuses a statement in which it may fail. -/

namespace Belay.Sqlite.Model.Resolved

/-- The number of columns of {lit}`json_each`: {lit}`key`, {lit}`value`, {lit}`type`,
{lit}`atom`, {lit}`id`, {lit}`parent`, {lit}`fullkey`, {lit}`path`, and the hidden {lit}`json`
and {lit}`root`. -/
def eachWidth : Nat := 10

/-- The rows of the sources so far: the joined rows, the number of cells of each, and the
fault of the {lit}`json_each` calls among them. -/
structure SourceRows where
  /-- The joined rows. -/
  rows : List (List Value)
  /-- The number of cells of a joined row. -/
  width : Nat
  /-- {lean}`Fault.may` when a {lit}`json_each` call over a row so far fails, else
  {lean}`Fault.none`. -/
  fault : Fault

/-- The rows so far joined with one more source ({name}`joinRows`); none for a table that
the database does not have, a subquery, which the model does not run yet, and a pragma whose
rows the model does not give ({name}`PragmaRows.rowsOn`). The rows of
a {lit}`json_each` source are its rows over each row so far ({name}`joinRow`); resolution
refuses it as the right operand of a right or full join, where this gives the rows of an
inner or left join. -/
def QuerySource.join (context : EvalContext) (database : Database) (state : SourceRows) (join : QuerySource) : Option SourceRows :=
  match join.source with
  | .table position => (database.table position).map fun table =>
    { rows := joinRows context state.width state.rows join table.shape.columns.length (sourceRows table),
      width := state.width + table.shape.columns.length, fault := state.fault }
  | .each json path =>
    let results := state.rows.map fun row => (row, Json.eachRows (json.eval context row) (path.map (·.eval context row)))
    let failed := results.any fun (_, result) => match result with
      | .ok _ => false
      | .error _ => true
    some { rows := results.flatMap (fun (row, result) => joinRow context join eachWidth (result.toOption.getD []) row),
           width := state.width + eachWidth,
           fault := if failed then state.fault.join .may else state.fault }
  | .subquery => none
  | .pragma pragma => (pragma.rowsOn database).map fun rows =>
    { rows := joinRows context state.width state.rows join pragma.width rows, width := state.width + pragma.width,
      fault := state.fault }

/-- The source rows of a query over a database: its sources joined in written order
({name}`QuerySource.join`) from the one row with no cells, which is the source of a query
without {lit}`FROM`; none when a table is missing. -/
def Query.source (context : EvalContext) (query : Query) (database : Database) : Option SourceRows :=
  query.sources.foldlM (QuerySource.join context database) { rows := [[]], width := 0, fault := .none }

/-- For every context, database, list of sources without a {lit}`json_each` source and state whose
fault is {lean}`Fault.none`, a successful fold of {name}`QuerySource.join` ends with the fault
{lean}`Fault.none`. Proof sketch: induction on the sources; a table source keeps the fault,
a pragma keeps the fault, and a subquery stops the fold. -/
theorem source_fault_of_plain (context : EvalContext) (database : Database) :
    ∀ (sources : List QuerySource) (state result : SourceRows), sources.all (!·.source.isEach) = true →
      state.fault = .none → sources.foldlM (QuerySource.join context database) state = some result → result.fault = .none
  | [], state, result, _, clean, done => by
    simp only [List.foldlM, pure] at done
    cases done
    exact clean
  | join :: rest, state, result, plain, clean, done => by
    simp only [List.all_cons, Bool.and_eq_true] at plain
    simp only [List.foldlM, bind, Option.bind] at done
    obtain ⟨kind, source, condition⟩ := join
    cases source with
    | table position =>
      simp only [QuerySource.join] at done
      cases found : database.table position with
      | none => simp [found] at done
      | some table =>
        simp only [found, Option.map_some] at done
        refine source_fault_of_plain context database rest _ result plain.2 ?_ done
        exact clean
    | each json path => simp [Source.isEach] at plain
    | subquery => simp [QuerySource.join] at done
    | pragma pragma =>
      simp only [QuerySource.join] at done
      cases found : pragma.rowsOn database with
      | none => simp [found] at done
      | some rows =>
        simp only [found, Option.map_some] at done
        refine source_fault_of_plain context database rest _ result plain.2 ?_ done
        exact clean

end Belay.Sqlite.Model.Resolved
