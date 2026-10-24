import Belay.Sqlite.Model.Counters
import Belay.Sqlite.Model.Execution

set_option doc.verso true

/-! The connection state of script-directed SQL execution: the visible database, the
snapshot of an open transaction, the clock assignment and the counters, the transitions of one
statement, and the one path that publishes a statement's effect (ADR 0013, D8). -/

namespace Belay.Sqlite.Model

/-- The current connection view, optional transaction snapshot, clock assignment and counters.
Supply a database and omit the snapshot for an idle connection. -/
structure SqlState where
  /-- Current connection-visible storage. -/
  database : Database
  /-- Pre-BEGIN committed storage; omit it outside a transaction. -/
  snapshot : Option Database := none
  /-- The clock value of the statement at each zero-based position, in SQLite's Julian-day
  milliseconds; 0 at every position by default, for a script that reads no clock. -/
  clock : Nat → Int := fun _ => 0
  /-- The counters that {lit}`changes()`, {lit}`total_changes()` and {lit}`last_insert_rowid()`
  read ({name}`Counters`); unknown by default. A rollback restores the database and leaves
  them. -/
  counters : Counters := {}

/-- Attach an open transaction to a terminal result. A success becomes pending
without an error; a failure becomes pending with its position/error. An existing
pending result is retained. With no snapshot, return the supplied outcome. -/
def SqlState.finish (state : SqlState) (outcome : Outcome) : Outcome :=
  match state.snapshot, outcome with
  | none, _ => outcome
  | some original, .success result => .pending original result none
  | some original, .failure index reason result => .pending original result (some (index, reason))
  | _, .pending .. => outcome

/-- The outcome of a statement that fails: a ROLLBACK failure in an open transaction
rolls it back, so it is the failure over the snapshot outside a transaction; every other
failure, and a ROLLBACK failure without a transaction, is {name}`SqlState.finish` of the
failure. -/
def SqlState.failed (state : SqlState) (position : Nat) (reason : ExecutionError) (database : Database) : Outcome :=
  if reason = .constraintRollback then match state.snapshot with
    | some original => .failure position reason original
    | none => state.finish (.failure position reason database)
  else state.finish (.failure position reason database)

/-- One SQL transition either continues with a connection state or halts with an
{name}`Outcome`. Evaluate a supplied statement to obtain a transition. -/
inductive SqlTransition where
  /-- Continue with this updated connection state. -/
  | next (state : SqlState)
  /-- Stop with this error or terminal result. -/
  | halt (outcome : Outcome)

/-- The transition of a statement's effect at its position, the one path that publishes
the result of a statement (ADR 0013, D8): an effect that succeeds continues with its
database; an error halts with the database that its algorithm keeps: the database that a
FAIL failure reached ({lean}`ExecutionError.constraintFail`), which keeps the earlier rows,
the input database for every other error, and the snapshot for ROLLBACK in a transaction
({name}`SqlState.failed`). -/
def SqlState.publish (state : SqlState) (position : Nat) : Effect → SqlTransition
  | .ok database => .next { state with database }
  | .error (reason, reached) =>
    .halt (state.failed position reason (if reason = .constraintFail then reached else state.database))

end Belay.Sqlite.Model
