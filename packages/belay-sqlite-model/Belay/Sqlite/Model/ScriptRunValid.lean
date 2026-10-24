import Belay.Sqlite.Model.ScriptRunAdmittedRows
import Belay.Sqlite.Model.ScriptRunConstraints

set_option doc.verso true

/-! The corollary of the run theorems (ADR 0022, D3, slice 4): a run of {lit}`runScriptFrom`, the run of
the surface, from a connection whose database and snapshot are valid ({lit}`Database.Valid`) ends in a
connection whose database and snapshot are valid, for a context in execution mode with the limits of the
profile. It needs no hypothesis on the statements of the script. ADR 0017, S4 uses it to remove the check
{lit}`Run.checked`. {lit}`runScriptStep_valid` is the same for one statement, which the surface uses for the
programs ({lit}`Sql.runFrom`) in the induction of {lit}`Sql.runFrom_valid`. -/

namespace Belay.Sqlite.Model

/-- For every profile and database: it is valid under the profile ({name}`Database.Valid`) exactly when it is
admitted and satisfies the four constraint atoms ({name}`Database.ConstraintAtoms`). Proof sketch: the fields
of the structure. -/
theorem Database.valid_iff {profile : Profile} {database : Database} :
    database.Valid profile ↔ database.AdmittedWith profile Database.ConstraintAtoms :=
  ⟨fun valid => ⟨valid.admitted, valid.constraintAtoms⟩,
    fun ⟨admitted, notNull, typesFit, checks, unique⟩ => ⟨admitted, notNull, checks, typesFit, unique⟩⟩

/-- For every profile: the empty database ({lean}`({} : Database)`, with no table and no row) is valid
({name}`Database.Valid`). A new connection starts from it, so the corollary applies to every run on a new
connection. Proof sketch: the catalog is empty, so it is valid, and every atom about the tables holds
because the database has no table. -/
theorem Database.valid_empty (profile : Profile) : (({} : Database)).Valid profile := by
  have noTable : ∀ position, ({} : Database).table position = none := fun position => by
    simp [Database.table, Catalog.tableAt]
  have vacuous : ∀ {property : Nat → Table → Prop}, ({} : Database).EveryTable property :=
    fun position table present => by simp [noTable] at present
  exact ⟨⟨(rfl : Catalog.supported profile.limits [] = true), ⟨rfl, fun _ _ => rfl⟩, vacuous, vacuous, vacuous, vacuous,
    vacuous⟩, vacuous, vacuous, vacuous, vacuous⟩

/-- The corollary of the run theorems for {name}`runScriptFrom`. For every profile, context in execution mode
with the limits of the profile ({lit}`context.profile.limits = profile.limits`), clock, index, connection and
statements with their values: if the state of the connection satisfies {name}`SqlState.Holds` for
{name}`Database.Valid` (its database, and its snapshot when a transaction is open), the state of the
connection of the run ({lit}`connection.state`) satisfies it. It has no hypothesis on the statements of the
script: a CREATE INDEX, an ADD COLUMN, a DROP, a write that cascades, a trigger and a ROLLBACK all keep the
database valid. Proof sketch: {name}`runScriptFrom_constraintAtoms`, with {name}`Database.valid_iff` for the
start state and the end state. -/
theorem runScriptFrom_valid {profile : Profile} (context : ResolveContext) (clock : Option Clock) (index : Nat)
    {connection : Connection} (script : List (Syntax.Statement × List Value))
    (execution : context.mode = .execution) (same : context.profile.limits = profile.limits)
    (holds : connection.state.Holds (Database.Valid profile)) :
    (runScriptFrom context clock index connection script).connection.state.Holds (Database.Valid profile) :=
  (runScriptFrom_constraintAtoms context clock index script execution same
    (holds.mono fun _ valid => Database.valid_iff.mp valid)).mono fun _ atoms => Database.valid_iff.mpr atoms

/-- The corollary of the run theorems for one statement ({name}`runScriptStep`), the step of a program of the
surface. For every profile, context in execution mode with the limits of the profile, clock, index,
connection, statement and values: if the state of the connection satisfies {name}`SqlState.Holds` for
{name}`Database.Valid`, and the step continues with a next connection, the state of the next connection
satisfies it. Proof sketch: {name}`runScriptFrom_valid` for the script of the statement, whose run is the
step followed by the empty script. -/
theorem runScriptStep_valid {profile : Profile} (context : ResolveContext) (clock : Option Clock) (index : Nat)
    {connection : Connection} (statement : Syntax.Statement) (values : List Value)
    (execution : context.mode = .execution) (same : context.profile.limits = profile.limits)
    (holds : connection.state.Holds (Database.Valid profile)) {output : Output} {next : Connection}
    (continued : runScriptStep context clock index connection statement values = .continued output next) :
    next.state.Holds (Database.Valid profile) := by
  have kept := runScriptFrom_valid context clock index [(statement, values)] execution same holds
  simpa [runScriptFrom, continued] using kept

end Belay.Sqlite.Model
