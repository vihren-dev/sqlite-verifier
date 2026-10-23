import Belay.Sqlite.Model.Resolution.Resolved
import Belay.Sqlite.Model.ClockReads
import Belay.Sqlite.Model.StoreValue
import Belay.Sqlite.Model.JsonReady

set_option doc.verso true

/-! The clock of a resolved statement (ADR 0012, amendment 5, slice 6e2; ADR 0013, D6): the
cells of INSERT rows in the statement's evaluation context, whose clock value is the
statement's, and whether a statement reads the clock at all. Evaluation takes the context
as a parameter, so a statement is never rewritten for a clock value. -/

namespace Belay.Sqlite.Model.Resolved

/-- The value of an INSERT cell in an evaluation context, for a column of the affinity: a value
cell is its value, which resolution stored already; an expression cell is the value of its
expression in the context, which reads no column, stored with the affinity
({name}`Value.store`). -/
def Cell.valueAt (context : EvalContext) (affinity : Affinity) : Cell → Value
  | .value stored => stored
  | .expression term => Value.store affinity (term.eval context [])

/-- The rows of an INSERT in an evaluation context: each cell's value ({name}`Cell.valueAt`) for the
affinity of its column; a cell past the last column has BLOB affinity. -/
def rowsAt (context : EvalContext) (columns : List CatalogColumn) (rows : List (List Cell)) : List (List Value) :=
  rows.map fun row => row.zipIdx.map fun (cell, index) =>
    cell.valueAt context ((columns[index]?.map CatalogColumn.affinity).getD .blob)

/-- For every evaluation context, columns and rows whose cells are all values, the rows in
the context ({name}`rowsAt`) are those values: a script of known values reads nothing of the
context. -/
theorem rowsAt_values (context : EvalContext) (columns : List CatalogColumn) (rows : List (List Value)) :
    rowsAt context columns (rows.map (·.map Cell.value)) = rows := by
  have cells : ∀ (row : List Value),
      (row.map Cell.value).zipIdx.map (fun (cell, index) =>
        cell.valueAt context ((columns[index]?.map CatalogColumn.affinity).getD .blob)) = row := by
    intro row
    apply List.ext_getElem (by simp)
    intro index _ _
    simp [Cell.valueAt]
  simp only [rowsAt, List.map_map]
  conv => rhs; rw [← List.map_id rows]
  exact List.map_congr_left fun row _ => cells row

/-- The expression of an INSERT cell, if it has one. -/
def Cell.expression? : Cell → Option Expr
  | .value _ => none
  | .expression term => some term

/-- Every expression of a step of a trigger program that evaluation reads (ADR 0018, D5): the
expression cells of an INSERT and its clauses, the values and filters of writes, the expressions
of a query, those of each step's subqueries, and the filter and conditions of a raising SELECT. -/
def Step.expressions : Step → List Expr
  | .insert _ rows clauses _ subqueries =>
    rows.flatten.filterMap Cell.expression? ++ clauses.flatMap ConflictClause.expressions ++ subqueries.flatMap Query.expressions
  | .update _ assignments filter subqueries => assignments.map (·.2) ++ filter.toList ++ subqueries.flatMap Query.expressions
  | .delete _ filter subqueries => filter.toList ++ subqueries.flatMap Query.expressions
  | .query inner subqueries => inner.expressions ++ subqueries.flatMap Query.expressions
  | .raise filter arms _ => filter.toList ++ arms.map (·.1)

/-- Every expression of the trigger programs of a write's rules: the condition and the steps of
each program ({name}`Step.expressions`); none without rules. -/
def WriteRules.expressions (rules : Option WriteRules) : List Expr :=
  (rules.map fun rules => rules.programs.flatMap fun program =>
    program.condition.toList ++ program.body.flatMap Step.expressions).getD []

/-- Every expression of a statement that evaluation reads: the expression cells of INSERT
rows ({name}`Cell.expression?`), the {lit}`RETURNING` columns, the values and filters of
writes, the clauses of an upsert ({name}`ConflictClause.expressions`), the expressions of a
query ({name}`Query.expressions`), those of each statement's subqueries, and those of the trigger
programs of a write ({name}`WriteRules.expressions`), DROP TABLE's included; a schema or
transaction statement and a prepare error have none. -/
def Statement.clockExpressions : Statement → List Expr
  | .insert _ rows returning subqueries rules =>
    rows.flatten.filterMap Cell.expression? ++ returning.map (·.1) ++ subqueries.flatMap Query.expressions ++
      WriteRules.expressions rules
  | .upsert _ rows clauses returning _ subqueries rules =>
    rows.flatten.filterMap Cell.expression? ++ clauses.flatMap ConflictClause.expressions ++ returning.map (·.1) ++
      subqueries.flatMap Query.expressions ++ WriteRules.expressions rules
  | .update _ assignments filter returning subqueries rules =>
    assignments.map (·.2) ++ filter.toList ++ returning.map (·.1) ++ subqueries.flatMap Query.expressions ++
      WriteRules.expressions rules
  | .delete _ filter returning subqueries rules =>
    filter.toList ++ returning.map (·.1) ++ subqueries.flatMap Query.expressions ++ WriteRules.expressions rules
  | .drop _ rules => WriteRules.expressions rules
  | .query inner subqueries => inner.expressions ++ subqueries.flatMap Query.expressions
  | .createTable .. | .createIndex .. | .createTrigger .. | .addColumn .. | .begin | .commit | .rollback
  | .prepareError _ | .setting _ => []

/-- Whether a statement reads the clock: it has an expression that reads it
({name}`Expr.readsClock`, {name}`Statement.clockExpressions`). The execution gives a
statement that does not the clock value 0, which it does not read ({lit}`runSqlAt`). -/
def Statement.readsClock (statement : Statement) : Bool :=
  statement.clockExpressions.any Expr.readsClock

/-- Whether no expression of the subqueries of a statement has a fallible call
({name}`Resolved.Expr.isFallibleCall`): SQLite may evaluate a subquery for rows that the model
does not reach, so the model does not describe a failure inside one. -/
def subqueriesPlain (subqueries : List Resolved.Query) : Bool :=
  subqueries.all (·.expressions.all (!·.any Resolved.Expr.isFallibleCall))

/-- The subqueries of a statement's query without the terms of its compound
({name}`Resolved.Compound.terms`): SQLite runs each term of the statement's compound once, as a
query, and the compound describes their failures ({lit}`Compound.ending`). Every subquery for
a query that is not a compound. -/
def Query.nestedSubqueries (query : Resolved.Query) (subqueries : List Resolved.Query) : List Resolved.Query :=
  match query.compound with
  | none => subqueries
  | some compound => (subqueries.zipIdx.filter fun (_, index) => !compound.terms.contains index).map (·.1)

/-- Whether no expression cell of the rows of an INSERT may fail in the statement's context,
over the row without cells that SQLite evaluates them over: a subquery that it names has a
value that the model describes ({name}`Resolved.Fault.may` otherwise). -/
def cellsReady (context : Resolved.EvalContext) (rows : List (List Resolved.Cell)) : Bool :=
  !Resolved.anyMayFail context [[]] (rows.flatten.filterMap Resolved.Cell.expression?)

end Belay.Sqlite.Model.Resolved
