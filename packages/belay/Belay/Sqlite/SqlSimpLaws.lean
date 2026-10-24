import Belay.Sqlite.SqlSimp
import Belay.Sqlite.Model

set_option doc.verso true

/-! The laws of the simp set {lit}`sql_simp` (ADR 0017, S4): the evaluation of the resolved
expressions of a condition ({lit}`Model/ExprEvalLaws.lean`), their resolution from the written
condition ({lit}`Model/ExprResolutionLaws.lean`) and their calm ({lit}`Model/ExprCalmLaws.lean`); the subquery expressions are in the set with the shapes of a
statement with one subquery ({lit}`Model/SubqueryExprResolutionLaws.lean`).
A proof of a claim over every database writes {lit}`simp [sql_simp]` with the facts about the
catalog, and gets the claim in terms of the rows of the table. The unfolding of the monad of the
resolver and of the value of a written number are in the set too. -/

attribute [sql_simp]
  Belay.Sqlite.Model.Resolved.Expr.eval_column
  Belay.Sqlite.Model.Resolved.Expr.eval_literal
  Belay.Sqlite.Model.Resolved.Expr.eval_parameter
  Belay.Sqlite.Model.Resolved.Expr.eval_compare
  Belay.Sqlite.Model.Resolved.Expr.eval_and
  Belay.Sqlite.Model.Resolved.Expr.eval_or
  Belay.Sqlite.Model.Resolved.Expr.eval_not
  Belay.Sqlite.Model.Resolved.Expr.eval_isNull
  Belay.Sqlite.Model.Resolved.truthy_and
  Belay.Sqlite.Model.Resolved.truthy_or
  Belay.Sqlite.Model.Resolved.truthy_not
  Belay.Sqlite.Model.Resolved.truthy_apply_ordinary
  Belay.Sqlite.Model.resolveOperand_null
  Belay.Sqlite.Model.resolveOperand_string
  Belay.Sqlite.Model.resolveOperand_parameter
  Belay.Sqlite.Model.resolveOperand_numeric
  Belay.Sqlite.Model.resolveOperand_negate_numeric
  Belay.Sqlite.Model.Scope.columns_single
  Belay.Sqlite.Model.resolveName_one_source
  Belay.Sqlite.Model.resolveOperand_identifier_single
  Belay.Sqlite.Model.resolveOperand_identifier_table
  Belay.Sqlite.Model.resolveOperand_compare
  Belay.Sqlite.Model.resolveOperand_collate
  Belay.Sqlite.Model.resolveOperand_and
  Belay.Sqlite.Model.resolveOperand_or
  Belay.Sqlite.Model.resolveOperand_not
  Belay.Sqlite.Model.resolveOperand_isNull
  Belay.Sqlite.Model.resolveOperand_between
  Belay.Sqlite.Model.resolveOperand_not_between
  Belay.Sqlite.Model.Resolved.Expr.calm_column
  Belay.Sqlite.Model.Resolved.Expr.calm_literal
  Belay.Sqlite.Model.Resolved.Expr.calm_parameter
  Belay.Sqlite.Model.Resolved.Expr.calm_compare
  Belay.Sqlite.Model.Resolved.Expr.calm_and
  Belay.Sqlite.Model.Resolved.Expr.calm_or
  Belay.Sqlite.Model.Resolved.Expr.calm_not
  Belay.Sqlite.Model.Resolved.Expr.calm_isNull
  Belay.Sqlite.Model.Resolved.Expr.eval_exists
  Belay.Sqlite.Model.Resolved.Expr.eval_subquery
  Belay.Sqlite.Model.Resolved.Expr.eval_inQuery
  Belay.Sqlite.Model.Resolved.Expr.calm_exists
  Belay.Sqlite.Model.Resolved.Expr.calm_subquery
  Belay.Sqlite.Model.Resolved.Expr.calm_inQuery
  Belay.Sqlite.Model.resolveOperand_exists
  Belay.Sqlite.Model.resolveOperand_subquery
  Belay.Sqlite.Model.resolveOperand_inQuery
  Belay.Sqlite.Model.SubqueryShapes.find_only
  Belay.Sqlite.Model.SubqueryShapes.column_only
  Belay.Sqlite.Model.Resolved.EvalContext.withRuns_subqueries
  Belay.Sqlite.Model.Resolved.EvalContext.withRuns_parameters
  Belay.Sqlite.Model.Resolved.EvalContext.bound_parameters
  Belay.Sqlite.Model.parameterValue
  Belay.Sqlite.Model.Collation.compare_integer
  Belay.Sqlite.Model.Collation.binary_compare_text
  Belay.Sqlite.Model.resolveOperand_tableInfo_name
  Belay.Sqlite.Model.tableInfoScope_resolveName_name
  Belay.Sqlite.Model.tableInfoScope_collation_name
  Belay.Sqlite.Model.Resolved.countRows_eval
  Belay.Sqlite.Model.Resolved.Aggregate.eval_sum
  Belay.Sqlite.Model.Resolved.Aggregate.fails_sum
  Belay.Sqlite.Model.Resolved.Aggregate.fails_countRows
  Belay.Sqlite.Model.sumOf_fails_iff
  Belay.Sqlite.Model.sumOf_value_of_fits
  Belay.Sqlite.Model.Resolved.countMatching_none
  Except.map Except.mapError Except.bind Bind.bind Belay.Sqlite.Model.condition
  Belay.Sqlite.Model.queryNumeric Belay.Sqlite.Model.numericValue Belay.Sqlite.Model.decimalNumericValue
  Belay.Sqlite.Model.digitsValue Belay.Sqlite.Model.hexDigit Belay.Sqlite.Model.fitsInt64
  Belay.Sqlite.Model.tableScope Belay.Sqlite.Model.comparisonCollation
  Belay.Sqlite.Model.Syntax.Expr.explicitCollation Belay.Sqlite.Model.Syntax.Expr.columnCollation

attribute [grind =]
  Belay.Sqlite.Model.Resolved.countRows_eval
  Belay.Sqlite.Model.Resolved.Aggregate.eval_sum
  Belay.Sqlite.Model.Resolved.Aggregate.fails_sum
  Belay.Sqlite.Model.Resolved.Aggregate.fails_countRows
