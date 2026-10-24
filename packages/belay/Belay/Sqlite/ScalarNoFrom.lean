import Belay.Sqlite.QueryBridge
import Belay.Sqlite.Model

set_option doc.verso true

/-! Scalar no-FROM queries, including fallible functions. Resolution supplies the scalar
expression; these observations retain its run fault, including faults in the filter. -/

namespace Belay.Sqlite

open Belay.Sqlite.Model

/-- For every query script whose first statement resolves to a quiet no-FROM scalar SELECT,
it has a row exactly when its run has no fault and its optional condition passes.
Quiet excludes clocks and counters but permits fallible functions. A may-fault establishes
none of the three claims. Proof sketch: the common script/query bridge, the simple-query
fault observation, and the single empty source row of a no-FROM query. -/
theorem Holds.iff_noFrom_scalar
    {script : Script} {db : Database} {isQuery : script.isQuery = true}
    {statement : Syntax.Statement} {parameters : List Value} {rest : List (Syntax.Statement × List Value)}
    {condition : Option Resolved.Expr} {expression : Resolved.Expr} {names : List String} {after : ResolveState}
    (head : script.statements = (statement, parameters) :: rest)
    (resolved : resolveStatement runContext db.raw.connection.resolveState statement =
      .ok (.query (Resolved.Query.simple [] condition [.scalar expression] names) [], after))
    (quiet : (Resolved.Statement.query (Resolved.Query.simple [] condition [.scalar expression] names) []).Quiet) :
    Holds script db isQuery ↔
      ((Resolved.Query.simple [] condition [.scalar expression] names).run
        (Resolved.EvalContext.bound parameters) [[]]).fault = .none ∧
      condition.all (fun part => Resolved.truthy (part.eval (Resolved.EvalContext.bound parameters) [])) = true := by
  unfold Holds
  rw [Script.outputOn_query script db statement parameters rest _ [] after head resolved, Option.any_some]
  rw [resolvedStepOutput_simple_fault_hasRows 0 db.raw.connection parameters _
    (Resolved.Query.simple_isSimple _ _ _ _) { rows := [[]], width := 0, fault := .none } quiet
    (Resolved.Query.source_none _ _ _ rfl) rfl,
    Connection.queryContext_of_quiet db.raw.connection parameters _ quiet]
  simp [Resolved.Query.simple]

/-- For every query script whose first statement resolves to a quiet no-FROM scalar SELECT,
it has no rows exactly when its run has no fault and its optional condition does not pass.
Quiet excludes clocks and counters but permits fallible functions. A may-fault establishes
none of the three claims. Proof sketch: the common script/query bridge, the simple-query
fault observation, and the single empty source row of a no-FROM query. -/
theorem Empty.iff_noFrom_scalar
    {script : Script} {db : Database} {isQuery : script.isQuery = true}
    {statement : Syntax.Statement} {parameters : List Value} {rest : List (Syntax.Statement × List Value)}
    {condition : Option Resolved.Expr} {expression : Resolved.Expr} {names : List String} {after : ResolveState}
    (head : script.statements = (statement, parameters) :: rest)
    (resolved : resolveStatement runContext db.raw.connection.resolveState statement =
      .ok (.query (Resolved.Query.simple [] condition [.scalar expression] names) [], after))
    (quiet : (Resolved.Statement.query (Resolved.Query.simple [] condition [.scalar expression] names) []).Quiet) :
    Empty script db isQuery ↔
      ((Resolved.Query.simple [] condition [.scalar expression] names).run
        (Resolved.EvalContext.bound parameters) [[]]).fault = .none ∧
      condition.all (fun part => Resolved.truthy (part.eval (Resolved.EvalContext.bound parameters) [])) = false := by
  unfold Empty
  rw [Script.outputOn_query script db statement parameters rest _ [] after head resolved, Option.any_some]
  rw [resolvedStepOutput_simple_fault_hasNoRows 0 db.raw.connection parameters _
    (Resolved.Query.simple_isSimple _ _ _ _) { rows := [[]], width := 0, fault := .none } quiet
    (Resolved.Query.source_none _ _ _ rfl) rfl,
    Connection.queryContext_of_quiet db.raw.connection parameters _ quiet]
  simp [Resolved.Query.simple]

/-- For every query script whose first statement resolves to a quiet no-FROM scalar SELECT,
it fails exactly when its run has a must-fault.
Quiet excludes clocks and counters but permits fallible functions. A may-fault establishes
none of the three claims. Proof sketch: the common script/query bridge, the simple-query
fault observation, and the single empty source row of a no-FROM query. -/
theorem Fails.iff_noFrom_scalar
    {script : Script} {db : Database} {isQuery : script.isQuery = true}
    {statement : Syntax.Statement} {parameters : List Value} {rest : List (Syntax.Statement × List Value)}
    {condition : Option Resolved.Expr} {expression : Resolved.Expr} {names : List String} {after : ResolveState}
    (head : script.statements = (statement, parameters) :: rest)
    (resolved : resolveStatement runContext db.raw.connection.resolveState statement =
      .ok (.query (Resolved.Query.simple [] condition [.scalar expression] names) [], after))
    (quiet : (Resolved.Statement.query (Resolved.Query.simple [] condition [.scalar expression] names) []).Quiet) :
    Fails script db isQuery ↔
      ((Resolved.Query.simple [] condition [.scalar expression] names).run
        (Resolved.EvalContext.bound parameters) [[]]).fault = .must := by
  unfold Fails
  rw [Script.outputOn_query script db statement parameters rest _ [] after head resolved, Option.any_some]
  rw [resolvedStepOutput_simple_fault_isError 0 db.raw.connection parameters _
    (Resolved.Query.simple_isSimple _ _ _ _) { rows := [[]], width := 0, fault := .none } quiet
    (Resolved.Query.source_none _ _ _ rfl) rfl,
    Connection.queryContext_of_quiet db.raw.connection parameters _ quiet]

end Belay.Sqlite
