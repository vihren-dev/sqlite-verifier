import Belay.Sqlite.ProgramLaws

set_option doc.verso true

/-! How the surface's runs compose ({lit}`Run.lean`). Running is an action of the monoid of
scripts: {lit}`Script.runOn_append` and {lit}`Database.Raw.run_append` state the run of
{lit}`p ++ q` over the state of the connection, and {lit}`Script.run_append` states the guide's
form over {lit}`(db.run p).db`, for a {lit}`p` that ends outside a transaction, leaves foreign
keys off as it found them, and has no {lit}`Output.unmodeled`. -/

namespace Belay.Sqlite

/-- For every connection and all scripts {lit}`p` and {lit}`q`: the run of {lit}`p ++ q` on the
connection is the run of {lit}`p`, then ({name}`ScriptRun.andThen`) the run of {lit}`q` on the
connection that {lit}`p` left. When the run of {lit}`p` ends with {name}`Output.unmodeled`, it is
the run of {lit}`p` alone. Proof sketch: the model's
{name}`Belay.Sqlite.Model.runScriptFrom_append_constant`, for a run without a clock. -/
theorem Script.runOn_append (connection : Connection) (p q : Script) :
    (p ++ q).runOn connection = (p.runOn connection).andThen (q.runOn ·) :=
  Belay.Sqlite.Model.runScriptFrom_append_constant runContext none 0 connection p.statements q.statements
    (fun _ none => nomatch none)

/-- For every plain database and all scripts {lit}`p` and {lit}`q`: the run of {lit}`p ++ q` is the
run of {lit}`p`, then ({name}`ScriptRun.andThen`) the run of {lit}`q` on the connection that
{lit}`p` left: with its database, a transaction that {lit}`p` began and did not end, and its
setting of {lit}`PRAGMA foreign_keys`. When the run of {lit}`p` ends with
{name}`Output.unmodeled`, it is the run of {lit}`p` alone. Proof sketch:
{name}`Script.runOn_append` on the idle connection. -/
theorem Database.Raw.run_append (raw : Database.Raw) (p q : Script) :
    raw.run (p ++ q) = (raw.run p).andThen (q.runOn ·) :=
  Script.runOn_append raw.connection p q

/-- For every start database and model result of a program, the outputs of the checked run
({name}`Run.checked`) depend only on the result's outputs and connection: its outputs when the
database at its end is valid or when the model's run ended, and otherwise its outputs and the
output {name}`Output.unmodeled` with {name}`invalidReason`. Proof sketch: a case split on the
validity of the database at the end; each case unfolds {name}`Run.checked`. -/
theorem Run.checked_outputs {α : Type} (start : Database) (result : SqlRun α) :
    (Run.checked start result).outputs =
      if result.connection.state.database.Valid Profile.pinned ∨ result.ended then result.outputs
      else result.outputs ++ [.unmodeled invalidReason] := by
  unfold Run.checked
  by_cases valid : result.connection.state.database.Valid Profile.pinned <;> simp [valid]

/-- For every start database and model result of a program: if no output of the checked run ends
a run ({name}`Output.endsRun`), the database at the end of the result is valid, the model's run
did not end ({name}`ScriptRun.ended`), and the checked run gives the result's value, that
database, the result's outputs, its open transaction and its settings. Proof sketch: an invalid
result gives an output {name}`Output.unmodeled`, from the result or from the check. -/
theorem Run.checked_modeled {α : Type} {start : Database} {result : SqlRun α}
    (modeled : ∀ output ∈ (Run.checked start result).outputs, output.endsRun = false) :
    ∃ valid : result.connection.state.database.Valid Profile.pinned, result.ended = false ∧
      Run.checked start result =
        { value := result.value, outputs := result.outputs, db := ⟨_, valid⟩, start := start,
          transaction := result.connection.state.snapshot, foreignKeys := result.connection.foreignKeys,
          recursiveTriggers := result.connection.recursiveTriggers } := by
  unfold Run.checked at modeled ⊢
  by_cases valid : result.connection.state.database.Valid Profile.pinned
  · rw [dite_eq_left valid] at modeled ⊢
    exact ⟨valid, by simpa [ScriptRun.ended] using modeled, rfl⟩
  · rw [dite_eq_right valid] at modeled
    cases ended : result.ended
    · rw [ended, ite_eq_right Bool.false_ne_true] at modeled
      have := modeled (.unmodeled invalidReason) (List.mem_append_right _ (List.mem_singleton_self _))
      simp [Output.endsRun] at this
    · rw [ended, ite_eq_left rfl] at modeled
      simp only [ScriptRun.ended, List.any_eq_true] at ended
      obtain ⟨output, member, ends⟩ := ended
      rw [modeled output member] at ends
      cases ends

/-- For every connection: if no transaction is open, foreign keys and recursive triggers are
off, and the clock is 0 at every position, the connection is the idle connection to its database
({name}`Database.Raw.connection`). Proof sketch: split the connection into its database,
snapshot, clock and settings; the hypotheses fix all of them except the database. -/
theorem Connection.eq_idle {connection : Connection} (outside : connection.state.snapshot = none)
    (setting : connection.foreignKeys = false) (recursive : connection.recursiveTriggers = false)
    (clock : connection.state.clock = fun _ => 0) :
    connection = Database.Raw.connection connection.state.database := by
  rcases connection with ⟨⟨database, snapshot, clockOf⟩, foreignKeys, recursiveTriggers⟩
  simp_all [Database.Raw.connection]

/-- The guide's form of {lit}`run_append`. For every database and all scripts {lit}`p` and
{lit}`q`: if the run of {lit}`p` ends with no open transaction, with foreign keys and recursive
triggers off as at the start of a run, and with no output {name}`Output.unmodeled` ({name}`Output.endsRun`), then the
outputs of the run of {lit}`p ++ q` are the outputs of the run of {lit}`p`, then the outputs of
the run of {lit}`q` on the database that the run of {lit}`p` gives. Proof sketch: each run of a
script is the checked run of S2's run ({name}`Database.run_script_default`); the run of
{lit}`p` is valid and did not end ({name}`Run.checked_modeled`), so it leaves the idle
connection to its database ({name}`Connection.eq_idle`); the plain runs compose
({name}`Database.Raw.run_append`), and the check at the end reads the same result on both
sides ({name}`Run.checked_outputs`). -/
theorem Script.run_append (db : Database) (p q : Script) (outside : (db.run p).transaction = none)
    (setting : (db.run p).foreignKeys = false) (recursive : (db.run p).recursiveTriggers = false)
    (modeled : ∀ output ∈ (db.run p).outputs, output.endsRun = false) :
    (db.run (p ++ q)).outputs = (db.run p).outputs ++ ((db.run p).db.run q).outputs := by
  simp only [Database.run_script_default] at outside setting recursive modeled ⊢
  obtain ⟨valid, quiet, checked⟩ := Run.checked_modeled modeled
  rw [checked] at outside setting recursive ⊢
  rw [Run.checked_outputs, Run.checked_outputs]
  simp only [SqlRun.ofScript_toScriptRun] at outside setting recursive quiet ⊢
  have idle := Connection.eq_idle outside setting recursive
    ((Belay.Sqlite.Model.runScriptFrom_clock runContext none 0 db.raw.connection p.statements).trans rfl)
  simp only [Database.Raw.run_append, ScriptRun.andThen, quiet, Bool.false_eq_true, ite_false]
  simp only [Database.Raw.run] at idle quiet ⊢
  simp only [← idle]
  simp only [ScriptRun.ended] at quiet
  simp only [ScriptRun.ended, List.any_append, quiet, Bool.false_or]
  generalize Script.runOn (Script.runOn db.raw.connection p).connection q = later
  by_cases continues : later.connection.state.database.Valid Profile.pinned ∨ later.outputs.any Output.endsRun = true
  · rw [ite_eq_left continues]
    exact congrArg (_ ++ ·) (ite_eq_left continues).symm
  · rw [ite_eq_right continues, List.append_assoc]
    exact congrArg (_ ++ ·) (ite_eq_right continues).symm

end Belay.Sqlite
