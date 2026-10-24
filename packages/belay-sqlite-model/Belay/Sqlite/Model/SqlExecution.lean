import Belay.Sqlite.Model.SqlAdvance

set_option doc.verso true

/-! Script-directed SQL execution of resolved statements with the clock (ADR 0012, amendment
5, slice 6e2; ADR 0013, D6). Each statement sees one clock value, which a clock assignment
gives for its position; evaluation takes it as a parameter ({lit}`SqlState.clock`). The
execution relation relates a script to the outcome of every clock assignment, so a
verification target quantifies over every clock value of every statement (ADR 0012, owner
decision 8). A statement that reads no clock ({lit}`Resolved.Statement.readsClock`) runs at
the clock value 0, which it does not read, so a script that reads no clock has the outcome
of {lit}`runSql` at every clock assignment. -/

namespace Belay.Sqlite.Model

/-- A clock assignment: the clock value that the statement at each zero-based position
sees, in SQLite's Julian-day milliseconds (what the VFS method {lit}`xCurrentTimeInt64`
returns). Use {lean}`(fun _ => 0 : Clock)` when no statement reads the clock. -/
abbrev Clock := Nat → Int

/-- The clock assignment with which a script runs: the clock value of the assignment for a
statement that reads the clock ({name}`Resolved.Statement.readsClock`), and 0 for every
other position. -/
def scriptClock (clock : Clock) (script : List Resolved.Statement) : Clock := fun position =>
  if (script[position]?).any Resolved.Statement.readsClock then clock position else 0

/-- Execute a resolved script, each statement with the values bound to its parameters, from
position zero outside a transaction under a clock assignment, with the clock values of
{name}`scriptClock` of its statements. -/
def runSqlAt (clock : Clock) (script : List (Resolved.Statement × List Value)) (database : Database) : Outcome :=
  runSqlFrom 0 script { database := database, clock := scriptClock clock (script.map (·.1)) }

/-- For the supplied script, each statement with the values bound to its parameters, and
database, and every clock assignment, the reached-statement data check
{name}`supportedSqlFrom` of the script with the clock values of {name}`scriptClock` of its
statements returns true. This does not assert native refinement or successful
execution. A verification target proves this obligation for every admitted database; it
is not an extra unproved premise. -/
def SupportedSql (script : List (Resolved.Statement × List Value)) (database : Database) : Prop :=
  ∀ clock : Clock,
    supportedSqlFrom 0 script { database := database, clock := scriptClock clock (script.map (·.1)) } = true

/-- Relate each profile, script (each statement with the values bound to its parameters) and
starting database to the outcome of every clock assignment ({name}`runSqlAt`). Every profile currently has this same semantics; the profile
remains bound into verification inputs. -/
inductive ProfileExecutes : Profile → List (Resolved.Statement × List Value) → Database → Outcome → Prop where
  /-- The computed SQL result under a clock assignment is related for every profile, script
  and database. -/
  | evaluated (clock : Clock) : ProfileExecutes profile script database (runSqlAt clock script database)

/-- For every profile, script and starting database, there exists a related outcome. The
computed result at any clock assignment supplies the witness, including empty scripts,
errors and pending transactions; outcome coverage is never vacuous. -/
theorem ProfileExecutes.total (profile : Profile) (script : List (Resolved.Statement × List Value))
    (database : Database) : ∃ outcome, ProfileExecutes profile script database outcome :=
  ⟨_, .evaluated fun _ => 0⟩

/-- For every related execution, there is a clock assignment under which its outcome is the
computed {name}`runSqlAt` result for the same script and starting database. The proof
inspects the relation constructor; there are no additional hypotheses. -/
theorem ProfileExecutes.result (execution : ProfileExecutes profile script database outcome) :
    ∃ clock, runSqlAt clock script database = outcome := by
  cases execution with
  | evaluated clock => exact ⟨clock, rfl⟩

/-- Whether at least one statement of the script reads the clock
({name}`Resolved.Statement.readsClock`). -/
def scriptReadsClock (script : List Resolved.Statement) : Bool :=
  script.any Resolved.Statement.readsClock

/-- For every clock assignment and every script that does not read the clock, the clock
assignment of the script ({name}`scriptClock`) is 0 at every position. Proof sketch: a
position in the script holds a statement that does not read the clock, and a position
past its end has no statement. -/
theorem scriptClock_of_readsClock (clock : Clock) (script : List Resolved.Statement)
    (free : scriptReadsClock script = false) : scriptClock clock script = fun _ => 0 := by
  funext position
  simp only [scriptReadsClock, List.any_eq_false, Bool.not_eq_true] at free
  simp only [scriptClock]
  cases found : script[position]? with
  | none => rfl
  | some statement => simp [free statement (List.mem_of_getElem? found)]

/-- For every clock assignment, database and script with values whose statements do not read
the clock, the execution under the clock assignment is {name}`runSql`. Proof sketch:
{name}`scriptClock_of_readsClock` turns the script's assignment into 0 at every position,
which is the default clock assignment of the state that {name}`runSql` starts from. -/
theorem runSqlAt_of_readsClock (clock : Clock) (script : List (Resolved.Statement × List Value)) (database : Database)
    (free : scriptReadsClock (script.map (·.1)) = false) : runSqlAt clock script database = runSql script database := by
  rw [runSqlAt, scriptClock_of_readsClock clock _ free]
  rfl

/-- For every script with values whose statements do not read the clock and every database: if
the support check
{name}`supportedSqlFrom` passes, the script is supported at every clock assignment. Proof
sketch: {name}`scriptClock_of_readsClock` turns every clock assignment of the script into 0 at
every position, so the support check at each assignment is the check at the zero clock, which
passes. -/
theorem SupportedSql.of_readsClock {script : List (Resolved.Statement × List Value)} {database : Database}
    (free : scriptReadsClock (script.map (·.1)) = false) (supported : supportedSqlFrom 0 script { database := database } = true) :
    SupportedSql script database := fun clock => by
  rw [scriptClock_of_readsClock clock _ free]
  exact supported

/-- For every related execution of a script with values whose statements do not read the
clock, its outcome is
the computed {name}`runSql` result. -/
theorem ProfileExecutes.result_of_readsClock (free : scriptReadsClock (script.map (·.1)) = false)
    (execution : ProfileExecutes profile script database outcome) : runSql script database = outcome := by
  obtain ⟨clock, executed⟩ := execution.result
  rw [← executed]
  exact (runSqlAt_of_readsClock clock script database free).symm

/-- For every profile, database and script with values whose statements do not read the clock,
the computed
{name}`runSql` result is a related execution: it is the outcome at every clock assignment. -/
theorem ProfileExecutes.of_readsClock (free : scriptReadsClock (script.map (·.1)) = false) :
    ProfileExecutes profile script database (runSql script database) := by
  rw [← runSqlAt_of_readsClock (fun _ => 0) script database free]
  exact .evaluated _

end Belay.Sqlite.Model
