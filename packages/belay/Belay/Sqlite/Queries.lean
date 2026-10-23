import Lean.Elab.Tactic.Basic
import Belay.Sqlite.Run

set_option doc.verso true

/-! Queries as propositions over one database (ADR 0017, S2): {lit}`Holds q db`, {lit}`Empty q db`
and {lit}`Fails q db` state what the query {lit}`q` gives on {lit}`db`, for every result that
SQLite may give for it. Each one is decidable, so {lit}`decide` proves it, or its negation, for
a concrete database and query. The query is a script of one read-only statement: the argument
{lit}`query` checks it when the term elaborates, also for a query with parameters. -/

namespace Belay.Sqlite

open Belay.Sqlite.Model Lean Elab Tactic

/-- Whether the script is a query: exactly one statement, which only reads
({name}`Model.Syntax.Statement.readsOnly`). -/
def Script.isQuery (script : Script) : Bool :=
  match script.statements with
  | [(statement, _)] => statement.readsOnly
  | [] | _ :: _ :: _ => false

/-- The output of the first statement of the script on the database, with foreign keys off, as
on a new connection: {lean}`(none : Option Output)` for a script without statements. -/
def Script.outputOn (script : Script) (db : Database) : Option Output :=
  (db.raw.run script).outputs.head?

/-- The tactic that proves the argument {lit}`query` of {lit}`Holds`, {lit}`Empty` and
{lit}`Fails`, or gives an error that says what a query is. It tries {lit}`decide`, then
{lit}`rfl`: a script with a value {lit}`$x` or with an argument holds a free variable, which
{lit}`decide` refuses, and {name}`Script.isQuery` reads only the statements, so {lit}`rfl`
proves it. The proof {lit}`id rfl` has the type of the goal, so that the instances of
{lit}`Decidable` below match a proposition that holds it. -/
elab "check_query" : tactic => do
  try evalTactic (← `(tactic| first | decide | exact id rfl))
  catch _ => throwError "the script must be one read-only statement: a SELECT, or PRAGMA foreign_keys without a value; remove the other statements, or use Database.run"

/-- {lit}`Holds q db`: query {lit}`q` runs on {lit}`db` without error and gives at least one row,
for every result that SQLite may give for it. In terms of the formula: the output of
{lit}`q` on {lit}`db` ({name}`Script.outputOn`) is {name}`Output.rows` with at least one row, or
{name}`Output.oneOf` in which each result has at least one row. It does not hold when the
output is {name}`Output.unmodeled`, for example for a query that reads the clock. For example,
on a table {lit}`invoices` with a row of amount 0, {lit}`Holds (sql r"SELECT 1 FROM invoices WHERE amount = 0") db`. -/
def Holds (q : Script) (db : Database) (_query : q.isQuery = true := by check_query) : Prop :=
  (q.outputOn db).any Output.hasRows = true

/-- {lit}`Empty q db`: query {lit}`q` runs on {lit}`db` without error and gives no row, for every
result that SQLite may give for it. In terms of the formula: the output of {lit}`q` on
{lit}`db` is {name}`Output.rows` without rows, or {name}`Output.oneOf` in which each result has no
row. It does not hold when the output is {name}`Output.unmodeled`. -/
def Empty (q : Script) (db : Database) (_query : q.isQuery = true := by check_query) : Prop :=
  (q.outputOn db).any Output.hasNoRows = true

/-- {lit}`Fails q db`: query {lit}`q` fails on {lit}`db`: its output is {name}`Output.error`, with any
result code. It does not hold when the output is {name}`Output.unmodeled`. -/
def Fails (q : Script) (db : Database) (_query : q.isQuery = true := by check_query) : Prop :=
  (q.outputOn db).any Output.isError = true

instance (q : Script) (db : Database) (query : q.isQuery = true) : Decidable (Holds q db query) :=
  inferInstanceAs (Decidable (_ = true))

instance (q : Script) (db : Database) (query : q.isQuery = true) : Decidable (Empty q db query) :=
  inferInstanceAs (Decidable (_ = true))

instance (q : Script) (db : Database) (query : q.isQuery = true) : Decidable (Fails q db query) :=
  inferInstanceAs (Decidable (_ = true))

end Belay.Sqlite
