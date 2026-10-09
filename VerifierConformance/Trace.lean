import Belay.Sqlite.SqlExecution

/-! ADR 0004 observations follow production transitions, including open transactions.
The caller supplies the finite union of fixture, statement and native table names.
This module neither executes SQLite nor asserts native correspondence. -/

namespace Belay.Sqlite.Conformance

/-- Finite table observations retain absent names, metadata, cells and row identity. -/
abbrev Tables := List (String × Option Table)

/-- Insert a row in physical order using structural recursion the kernel reduces. -/
def insertRow (row : Row) : List Row → List Row
  | [] => [row]
  | head :: rest =>
    if row.rowid ≤ head.rowid then row :: head :: rest else head :: insertRow row rest

/-- Row order is canonical without changing production storage.
ponytail: quadratic sorting suits small fixtures; replace with a kernel-reducible
merge sort if measured corpus sizes make this a bottleneck. -/
def observeTables (names : List String) (database : Database) : Tables :=
  names.map fun name => (name, (database name).map fun table =>
    { table with rows := table.rows.foldr insertRow [] })

/-- A snapshot preserves both views and the exact modeled failure position. -/
structure Observation where
  visible : Tables
  persisted : Tables
  transactionOpen : Bool
  error : Option (Nat × ExecutionError)
  deriving Repr, DecidableEq

/-- Observe terminal and intermediate outcomes using the production view helpers. -/
def observeOutcome (names : List String) (outcome : Outcome) : Observation :=
  { visible := observeTables names outcome.database
    persisted := observeTables names outcome.persistedDatabase
    transactionOpen := match outcome with | .pending .. => true | _ => false
    error := match outcome with
      | .success _ => none
      | .failure position reason _ => some (position, reason)
      | .pending _ _ error => error }

/-- An intermediate state is observed without closing or committing its transaction. -/
def observeState (names : List String) (state : SqlState) : Observation :=
  observeOutcome names (state.finish (.success state.database))

/-- Include the initial snapshot and each executed statement; a halt ends the trace. -/
def traceFrom (names : List String) (position : Nat) (script : List Statement)
    (state : SqlState) : List Observation :=
  observeState names state ::
    match script with
    | [] => []
    | statement :: rest => match advance position statement state with
      | .next next => traceFrom names (position + 1) rest next
      | .halt outcome => [observeOutcome names outcome]

/-- A complete case begins outside a transaction, just like runSql. -/
def trace (names : List String) (script : List Statement) (initial : Database) :
    List Observation :=
  traceFrom names 0 script { database := initial }

/-- Instrumentation ends at precisely the production evaluator's outcome. -/
theorem traceFrom_final (names : List String) (position : Nat)
    (script : List Statement) (state : SqlState) :
    (traceFrom names position script state).getLast? =
      some (observeOutcome names (runSqlFrom position script state)) := by
  induction script generalizing position state with
  | nil => simp [traceFrom, runSqlFrom, observeState]
  | cons statement rest ih =>
    cases h : advance position statement state with
    | next next =>
      simp [traceFrom, runSqlFrom, h, List.getLast?_cons, ih]
    | halt outcome => simp [traceFrom, runSqlFrom, h]

/-- Concrete conformance traces and verifier proofs refer to the same execution. -/
theorem trace_final (names : List String) (script : List Statement) (initial : Database) :
    (trace names script initial).getLast? =
      some (observeOutcome names (runSql script initial)) :=
  traceFrom_final names 0 script { database := initial }

end Belay.Sqlite.Conformance
