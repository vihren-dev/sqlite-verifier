import Belay.Sqlite.Model.Database
import Belay.Sqlite.Model.Counters
import Belay.Sqlite.Model.Resolution.QueryForm
import Belay.Sqlite.Model.Comparison
import Belay.Sqlite.Model.Json.JsonApply
import Belay.Sqlite.Model.Functions.Scalar

set_option doc.verso true

/-! The parts of expression evaluation that are not recursive (ADR 0013, D2): the
{lit}`Fault` of a part and how faults combine, the fault of a JSON or scalar function
result, SQLite's truth test of a value, and the operands of a comparison after its affinity. -/

namespace Belay.Sqlite.Model.Resolved

/-- Whether a JSON function of an expression fails over a row. Use
{lean}`Fault.none` for an expression without a failing call. -/
inductive Fault where
  /-- No JSON call fails. -/
  | none
  /-- A JSON call fails, but SQLite may skip it, or its error is one that the model does
  not describe; also a value that the model does not describe, such as the first row of a
  scalar subquery that SQLite's plan chooses. -/
  | may
  /-- A JSON call fails where SQLite certainly evaluates it, with an error that the
  model describes. -/
  | must
  deriving Repr, DecidableEq

/-- The fault of two parts that SQLite both evaluates: the stronger one,
{lean}`Fault.may.join Fault.must = Fault.must`. -/
def Fault.join : Fault → Fault → Fault
  | .none, other => other
  | .may, .must => .must
  | .may, .none | .may, .may => .may
  | .must, .none | .must, .may | .must, .must => .must

/-- The fault of a part that SQLite may skip: a certain failure becomes possible,
{lean}`Fault.must.soften = Fault.may`. -/
def Fault.soften : Fault → Fault
  | .must => .may
  | .none => .none
  | .may => .may

/-- The fault of one JSON function result: {lit}`must` for malformed JSON, a bad path, bad
{lit}`json_valid` flags, the argument errors of {lit}`json_object` and the edit functions, and
{lit}`JSON cannot hold BLOB values` for a stored BLOB that is not JSONB, which the model
describes; {lit}`may` for JSONB that the model does not read (not valid, or not in the encoding
of its tree) and for the error position of malformed JSON, which it does not describe;
{lit}`none` for a value. -/
def Fault.ofJson : Except Json.JsonError Value → Fault
  | .error .malformed | .error (.badPath _) | .error .badFlags | .error .objectArgumentCount
  | .error .labelNotText | .error (.editArgumentCount _) | .error .blobValue => .must
  | .error .blobArgument | .error .unmodeledPosition => .may
  | .ok _ => .none

/-- Whether a REAL is not zero, as a condition. -/
def realTruthy (bits : UInt64) : Bool := (realScaled bits).any (· != 0)

/-- Whether a value is true as a condition, as SQLite's {lit}`sqlite3VdbeBooleanValue` gives
it: an integer that is not zero, a REAL that is not zero, and TEXT or BLOB whose numeric
prefix ({name}`atof`) is not zero; NULL is not true. So {lit}`'1ab'` and {lit}`'0.9'` are
true and {lit}`'abc'` is not. -/
def truthy : Value → Bool
  | .integer value => value != 0
  | .real bits => realTruthy bits
  | .text bytes | .blob bytes => realTruthy (atof bytes).1.toBits
  | .null => false

/-- Whether a value is false as a condition: not NULL and not true. -/
def falsy (value : Value) : Bool := !value.isNull && !truthy value

/-- The fault of a scalar function result: {lit}`must` for a failure that SQLite reports,
{lit}`may` for a value that the model does not describe, {lit}`none` for a value. -/
def Fault.ofFunction : Except FunctionFailure Value → Fault
  | .error .error => .must
  | .error .unmodeled => .may
  | .ok _ => .none

/-- The value of {lit}`iif` over its argument values, as SQLite's {lit}`CASE` code computes it:
the value after the first condition that is true ({name}`truthy`), else the last value of an
odd number of arguments, else NULL. For example, {lean}`iifValue [.integer 0, .integer 1, .integer 2] = .integer 2`. -/
def iifValue : List Value → Value
  | [] => .null
  | [value] => value
  | condition :: value :: rest => if truthy condition then value else iifValue rest

/-- A comparison operand after a numeric affinity: TEXT that looks like a number becomes
that number ({name}`numericText`); every other value stays, so an integer never goes
through a double. -/
def numericOperand : Value → Value
  | .text bytes => numericText bytes
  | value@(.null) | value@(.integer _) | value@(.real _) | value@(.blob _) => value

/-- Whether a value is TEXT. -/
def _root_.Belay.Sqlite.Model.Value.isText : Value → Bool
  | .text _ => true
  | .null | .integer _ | .real _ | .blob _ => false

/-- The operands of a comparison after SQLite applies its affinity (the comparison
opcodes of {lit}`sqlite3VdbeExec`): with INTEGER, REAL or NUMERIC, each TEXT operand that
looks like a number becomes that number ({name}`numericOperand`); with TEXT, when an operand
is TEXT, each number becomes its text ({name}`Value.store`), which the order would also give
otherwise; with BLOB or none, the operands stay. -/
def comparisonOperands : Option Affinity → Value → Value → Value × Value
  | some .integer, left, right | some .real, left, right | some .numeric, left, right =>
    (numericOperand left, numericOperand right)
  | some .text, left, right =>
    if left.isText || right.isText then (Value.store .text left, Value.store .text right) else (left, right)
  | some .blob, left, right | none, left, right => (left, right)

/-- How SQLite ends the run of a query, before the model softens the faults of a subquery
(ADR 0019, D3): a compound {lit}`SELECT` reads it for each of its terms, because SQLite runs a
term of a statement's compound as its own query. Use {lean}`RunEnd.done` for a run without a
failure. -/
inductive RunEnd where
  /-- The run ends without a failure. -/
  | done
  /-- The run may fail, or fails in a way that the model does not describe. -/
  | may
  /-- A function call certainly fails, with {lit}`Fault.must`. -/
  | function
  /-- An aggregate certainly overflows. {lit}`grouped` is true for a query with
  {lit}`GROUP BY`, which may give the rows of earlier groups before the error. -/
  | overflow (grouped : Bool)
  /-- A value of {lit}`LIMIT` or {lit}`OFFSET` is not an integer: {lit}`datatype mismatch`. -/
  | mismatch
  deriving Repr, DecidableEq

/-- The rows that a subquery gives for one outer row, with the fault of its evaluation
(ADR 0018, D1), and whether SQLite's plan can change the rows that a scalar subquery or
{lit}`IN` reads. Use {lean}`true` for both flags when the rows are certain. -/
structure SubqueryRun where
  /-- The result rows, in the order of the subquery. -/
  rows : List (List Value)
  /-- The fault of the subquery's expressions. -/
  fault : Fault
  /-- Whether the first value of the first row is the same in every order in which SQLite
  may give the rows; a scalar subquery reads it. -/
  firstCertain : Bool := true
  /-- Whether the first values of the rows are the same in every order in which SQLite may
  give the rows, as a multiset; {lit}`IN` reads them. -/
  rowsCertain : Bool := true
  /-- How the run ended without the softened fault ({name}`RunEnd`), which a compound
  {lit}`SELECT` reads for its terms. -/
  ending : RunEnd := .done

/-- What the evaluation of an expression reads besides its row (ADR 0018, D1): the
statement's clock value in Julian-day milliseconds, the results of the statement's
subqueries, by index, for the row of the expression that reads them, and the values bound to
the statement's parameters (ADR 0019, D1), and the counters of the connection (ADR 0024, D2). Use {lit}`EvalContext.plain` for a statement
without subqueries and without values. -/
structure EvalContext where
  /-- The statement's clock value. -/
  clock : Int
  /-- The results of subquery {lit}`index` for an outer row. -/
  subqueries : Nat → List Value → SubqueryRun
  /-- The values of the query's aggregates over the current group (ADR 0018, D3); empty
  outside the group of an aggregate query. -/
  aggregates : List Value := []
  /-- The values bound to the statement's parameters: item {lit}`n` from 1 is the value of
  parameter {lit}`n`. Empty for a statement that binds none, so that each parameter is NULL. -/
  parameters : List Value := []
  /-- The counters of the connection before the statement (ADR 0024, D2), which
  {lit}`changes()`, {lit}`total_changes()` and {lit}`last_insert_rowid()` read. A counter that
  the context does not know reads as NULL, and the run of the statement is then not described. -/
  counters : Counters := {}

/-- The context of a statement without subqueries at a clock value: a subquery that it
names gives no rows and no fault, which resolution never needs. -/
def EvalContext.plain (clock : Int) : EvalContext :=
  { clock, subqueries := fun _ _ => { rows := [], fault := .none } }

/-- Whether no subquery of the context has a fault or uncertain rows: for every index and
outer row, the fault of the subquery's run is {lean}`Fault.none`, and its first row and its
rows are certain ({name}`SubqueryRun.firstCertain`, {name}`SubqueryRun.rowsCertain`). -/
def EvalContext.Quiet (context : EvalContext) : Prop :=
  ∀ index row, (context.subqueries index row).fault = .none ∧ (context.subqueries index row).firstCertain = true ∧
    (context.subqueries index row).rowsCertain = true

/-- For every clock value, the plain context of the clock value is quiet
({name}`EvalContext.Quiet`). Proof sketch: the plain context gives the fault
{lean}`Fault.none` and certain rows for every index and outer row by definition. -/
theorem EvalContext.plain_quiet (clock : Int) : (EvalContext.plain clock).Quiet := fun _ _ => ⟨rfl, rfl, rfl⟩

end Belay.Sqlite.Model.Resolved
