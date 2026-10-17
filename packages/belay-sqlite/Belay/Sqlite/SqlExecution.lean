import Belay.Sqlite.StatementStep
import Belay.Sqlite.StatementClockLaws

set_option doc.verso true

/-! Script-directed SQL execution of resolved statements with the clock (ADR 0012, amendment
5, slice 6e2). Each statement sees one clock value, which a clock assignment gives for its
position; the execution applies it to each statement ({lit}`Statement.atClock`) and then
runs the script as {lit}`runSql` of {lit}`StatementStep.lean` does. The execution relation relates a
script to the outcome of every clock assignment, so a verification target quantifies over
every clock value of every statement (ADR 0012, owner decision 8). A script that does not
read the clock has the outcome of {lit}`runSql` at every clock assignment. -/

namespace Belay.Sqlite

/-- A clock assignment: the clock value that the statement at each zero-based position
sees, in SQLite's Julian-day milliseconds (what the VFS method {lit}`xCurrentTimeInt64`
returns). Use {lean}`(fun _ => 0 : Clock)` when no statement reads the clock. -/
abbrev Clock := Nat → Int

/-- A script under a clock assignment: each statement at the clock value of its position
({name}`Resolved.Statement.atClock`). The statements of the result read no clock. -/
def scriptAtClock (clock : Clock) (script : List Resolved.Statement) : List Resolved.Statement :=
  script.mapIdx fun position (statement : Resolved.Statement) => statement.atClock (clock position)

/-- Execute a resolved script from position zero outside a transaction under a clock
assignment: {name}`runSql` of the script under the clock assignment ({name}`scriptAtClock`). -/
def runSqlAt (clock : Clock) (script : List Resolved.Statement) (database : Database) : Outcome :=
  runSql (scriptAtClock clock script) database

/-- For the supplied script and database, and every clock assignment, the reached-statement
data check {name}`supportedSqlFrom` of the script under the clock assignment
({name}`scriptAtClock`) returns true. This does not assert native refinement or successful
execution. A verification target proves this obligation for every admitted database; it
is not an extra unproved premise. -/
def SupportedSql (script : List Resolved.Statement) (database : Database) : Prop :=
  ∀ clock : Clock, supportedSqlFrom 0 (scriptAtClock clock script) { database := database } = true

/-- Relate each profile, script and starting database to the outcome of every clock
assignment ({name}`runSqlAt`). Every profile currently has this same semantics; the profile
remains bound into verification inputs. -/
inductive ProfileExecutes : Profile → List Resolved.Statement → Database → Outcome → Prop where
  /-- The computed SQL result under a clock assignment is related for every profile, script
  and database. -/
  | evaluated (clock : Clock) : ProfileExecutes profile script database (runSqlAt clock script database)

/-- For every profile, script and starting database, there exists a related outcome. The
computed result at any clock assignment supplies the witness, including empty scripts,
errors and pending transactions; outcome coverage is never vacuous. -/
theorem ProfileExecutes.total (profile : Profile) (script : List Resolved.Statement)
    (database : Database) : ∃ outcome, ProfileExecutes profile script database outcome :=
  ⟨_, .evaluated fun _ => 0⟩

/-- For every related execution, there is a clock assignment under which its outcome is the
computed {name}`runSqlAt` result for the same script and starting database. The proof
inspects the relation constructor; there are no additional hypotheses. -/
theorem ProfileExecutes.result (execution : ProfileExecutes profile script database outcome) :
    ∃ clock, runSqlAt clock script database = outcome := by
  cases execution with
  | evaluated clock => exact ⟨clock, rfl⟩

/-- Whether no statement of the script reads the clock ({name}`Resolved.Statement.readsClock`). -/
def scriptReadsClock (script : List Resolved.Statement) : Bool :=
  script.any Resolved.Statement.readsClock

/-- For every clock assignment and every script that does not read the clock, the script
under the clock assignment is the script itself. Proof sketch: the two lists have the same
length, and each statement is unchanged at its clock value
({name}`Resolved.Statement.atClock_of_readsClock`). -/
theorem scriptAtClock_of_readsClock (clock : Clock) (script : List Resolved.Statement)
    (free : scriptReadsClock script = false) : scriptAtClock clock script = script := by
  simp only [scriptAtClock, scriptReadsClock, List.any_eq_false, Bool.not_eq_true] at free ⊢
  apply List.ext_getElem (by simp)
  intro index _ _
  simp only [List.getElem_mapIdx]
  exact Resolved.Statement.atClock_of_readsClock _ _ (free _ (List.getElem_mem _))

/-- For every clock assignment, database and script that does not read the clock, the
execution under the clock assignment is {name}`runSql`. -/
theorem runSqlAt_of_readsClock (clock : Clock) (script : List Resolved.Statement) (database : Database)
    (free : scriptReadsClock script = false) : runSqlAt clock script database = runSql script database := by
  rw [runSqlAt, scriptAtClock_of_readsClock clock script free]

/-- For every script that does not read the clock and every database: if the support check
{name}`supportedSqlFrom` passes, the script is supported at every clock assignment. -/
theorem SupportedSql.of_readsClock {script : List Resolved.Statement} {database : Database}
    (free : scriptReadsClock script = false) (supported : supportedSqlFrom 0 script { database := database } = true) :
    SupportedSql script database := fun clock => by
  rw [scriptAtClock_of_readsClock clock script free]
  exact supported

/-- For every related execution of a script that does not read the clock, its outcome is
the computed {name}`runSql` result. -/
theorem ProfileExecutes.result_of_readsClock (free : scriptReadsClock script = false)
    (execution : ProfileExecutes profile script database outcome) : runSql script database = outcome := by
  obtain ⟨clock, executed⟩ := execution.result
  rw [← executed]
  exact (runSqlAt_of_readsClock clock script database free).symm

/-- For every profile, database and script that does not read the clock, the computed
{name}`runSql` result is a related execution: it is the outcome at every clock assignment. -/
theorem ProfileExecutes.of_readsClock (free : scriptReadsClock script = false) :
    ProfileExecutes profile script database (runSql script database) := by
  rw [← runSqlAt_of_readsClock (fun _ => 0) script database free]
  exact .evaluated _

end Belay.Sqlite
