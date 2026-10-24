import Belay.Sqlite.Model.AtomsConditionsOfLink
import Belay.Sqlite.Model.KeysUniqueRuns
import Belay.Sqlite.Model.ScriptRunApplied
import Belay.Sqlite.Model.ScriptRunDerived
import Belay.Sqlite.Model.ValidAtomsRuns
import Belay.Sqlite.Model.ValidAtomsTogether

set_option doc.verso true

/-! The run theorems of the atoms "keys unique", "not null", "types fit" and "checks hold" for
{lit}`runScriptFrom`, the run of the surface (ADR 0022, D3, slices 2 and 3; slice 4 removes the hypotheses).
The start state has {lit}`Database.Admitted` and the atom, in its database and in its snapshot. The
admitted facts and the facts of the resolver give the condition of each statement that the run resolves
(CREATE INDEX, ADD COLUMN, DROP, and the CHECKs), so the theorems have no hypothesis on the statements of
the script. The hypotheses of the {lit}`runSqlFrom` theorems stay as they were. -/

namespace Belay.Sqlite.Model

/-- For the given profile and property of databases: the database is admitted under the profile
({name}`Database.Admitted`) and has the property. It is the invariant of the run theorems of
{lit}`runScriptFrom` for the atoms of slices 2 and 3. -/
abbrev Database.AdmittedWith (profile : Profile) (property : Database → Prop) (database : Database) : Prop :=
  database.Admitted profile ∧ property database

/-- The run theorem of {name}`runScriptFrom` for an atom of slices 2 and 3, for every statement theorem and
every way to give its condition. For every profile, atom and condition: if the statement theorem holds
({name}`StatementKeeps`), and an admitted database gives the condition for every statement whose catalog after
it is valid and that meets {name}`Resolved.Statement.SchemaLink`, then for every context in execution mode with
the limits of the profile, clock, index, connection and statements with their values: if the state of the
connection satisfies {name}`SqlState.Holds` for {name}`Database.AdmittedWith` the atom, the state of the
connection of the run satisfies it. Proof sketch: {name}`runScriptFrom_holds_derived` for the conjunction of
{name}`admitted_statementKeeps` and the statement theorem of the atom; the resolver gives the validity of the
catalog after the statement ({name}`resolveStatement_appliedValid`) and the link
({name}`resolveStatement_schemaLink`). -/
theorem runScriptFrom_admittedWith {profile : Profile} {atom : Database → Prop}
    {condition : Resolved.Statement → Database → Prop} (keeps : StatementKeeps atom condition)
    (derive : ∀ (database : Database) (statement : Resolved.Statement), database.Admitted profile →
      statement.AppliedValid profile.limits database → statement.SchemaLink database.catalog →
        condition statement database)
    (context : ResolveContext) (clock : Option Clock) (index : Nat) {connection : Connection}
    (script : List (Syntax.Statement × List Value)) (execution : context.mode = .execution)
    (same : context.profile.limits = profile.limits)
    (holds : connection.state.Holds (Database.AdmittedWith profile atom)) :
    (runScriptFrom context clock index connection script).connection.state.Holds (Database.AdmittedWith profile atom) :=
  runScriptFrom_holds_derived ((admitted_statementKeeps profile).and keeps.toReady) context clock
    (fun _ _ _ _ keep ok =>
      have applied := resolveStatement_appliedValid context execution same (keep.mono fun _ h => h.1.catalogSupported) ok
      ⟨applied, derive _ _ keep.1.1 applied
        (resolveStatement_schemaLink context _ _ _ _ (same ▸ keep.1.1.catalogSupported) ok)⟩) index script holds

/-- The run theorem of "keys unique" for {name}`runScriptFrom`. For every profile, context in execution mode
with the limits of the profile, clock, index, connection and statements with their values: if the state of the
connection satisfies {name}`SqlState.Holds` for {name}`Database.AdmittedWith` {name}`Database.KeysUnique` (its
database, and its snapshot when a transaction is open), the state of the connection of the run
({lit}`connection.state`) satisfies it. It has no hypothesis on the statements of the script: CREATE INDEX,
ADD COLUMN and DROP meet their run condition ({name}`Resolved.Statement.RunCondition`) by
{name}`Resolved.Statement.runCondition_of_link`. Proof sketch: {name}`runScriptFrom_admittedWith` for
{name}`keysUnique_statementKeeps`. -/
theorem runScriptFrom_keysUnique {profile : Profile} (context : ResolveContext) (clock : Option Clock)
    (index : Nat) {connection : Connection} (script : List (Syntax.Statement × List Value))
    (execution : context.mode = .execution) (same : context.profile.limits = profile.limits)
    (holds : connection.state.Holds (Database.AdmittedWith profile Database.KeysUnique)) :
    (runScriptFrom context clock index connection script).connection.state.Holds
      (Database.AdmittedWith profile Database.KeysUnique) :=
  runScriptFrom_admittedWith keysUnique_statementKeeps
    (fun _ statement admitted applied link => statement.runCondition_of_link admitted applied link)
    context clock index script execution same holds

/-- The run theorem of "not null" for {name}`runScriptFrom`. For every profile, context in execution mode with
the limits of the profile, clock, index, connection and statements with their values: if the state of the
connection satisfies {name}`SqlState.Holds` for {name}`Database.AdmittedWith` {name}`Database.NotNull` (its
database, and its snapshot when a transaction is open), the state of the connection of the run
({lit}`connection.state`) satisfies it. It has no hypothesis on the statements of the script: the rows of the
table of an ADD COLUMN are wide because the database is admitted. Proof sketch:
{name}`runScriptFrom_admittedWith` for {name}`notNull_statementKeeps`. -/
theorem runScriptFrom_notNull {profile : Profile} (context : ResolveContext) (clock : Option Clock)
    (index : Nat) {connection : Connection} (script : List (Syntax.Statement × List Value))
    (execution : context.mode = .execution) (same : context.profile.limits = profile.limits)
    (holds : connection.state.Holds (Database.AdmittedWith profile Database.NotNull)) :
    (runScriptFrom context clock index connection script).connection.state.Holds
      (Database.AdmittedWith profile Database.NotNull) :=
  runScriptFrom_admittedWith notNull_statementKeeps
    (fun _ statement admitted _ _ => statement.notNullCondition_of_admitted admitted)
    context clock index script execution same holds

/-- The run theorem of "types fit" for {name}`runScriptFrom`. For every profile, context in execution mode with
the limits of the profile, clock, index, connection and statements with their values: if the state of the
connection satisfies {name}`SqlState.Holds` for {name}`Database.AdmittedWith` {name}`Database.TypesFit` (its
database, and its snapshot when a transaction is open), the state of the connection of the run
({lit}`connection.state`) satisfies it. It has no hypothesis on the statements of the script: the rows of the
table of an ADD COLUMN are wide because the database is admitted, and the resolver refuses a column whose
default does not fit its strict type. Proof sketch: {name}`runScriptFrom_admittedWith` for
{name}`typesFit_statementKeeps`. -/
theorem runScriptFrom_typesFit {profile : Profile} (context : ResolveContext) (clock : Option Clock)
    (index : Nat) {connection : Connection} (script : List (Syntax.Statement × List Value))
    (execution : context.mode = .execution) (same : context.profile.limits = profile.limits)
    (holds : connection.state.Holds (Database.AdmittedWith profile Database.TypesFit)) :
    (runScriptFrom context clock index connection script).connection.state.Holds
      (Database.AdmittedWith profile Database.TypesFit) :=
  runScriptFrom_admittedWith typesFit_statementKeeps
    (fun _ statement admitted _ link => statement.typesFitCondition_of_link admitted link)
    context clock index script execution same holds

/-- The run theorem of "checks hold" for {name}`runScriptFrom`. For every profile, context in execution mode
with the limits of the profile, clock, index, connection and statements with their values: if the state of the
connection satisfies {name}`SqlState.Holds` for {name}`Database.AdmittedWith` {name}`Database.ChecksHold` (its
database, and its snapshot when a transaction is open), the state of the connection of the run
({lit}`connection.state`) satisfies it. It has no hypothesis on the statements of the script: the rows of the
table of an ADD COLUMN are wide, and its CHECK constraints read only columns below its width, because the
database is admitted. Proof sketch: {name}`runScriptFrom_admittedWith` for {name}`checksHold_statementKeeps`. -/
theorem runScriptFrom_checksHold {profile : Profile} (context : ResolveContext) (clock : Option Clock)
    (index : Nat) {connection : Connection} (script : List (Syntax.Statement × List Value))
    (execution : context.mode = .execution) (same : context.profile.limits = profile.limits)
    (holds : connection.state.Holds (Database.AdmittedWith profile Database.ChecksHold)) :
    (runScriptFrom context clock index connection script).connection.state.Holds
      (Database.AdmittedWith profile Database.ChecksHold) :=
  runScriptFrom_admittedWith checksHold_statementKeeps
    (fun _ statement admitted _ _ => statement.checksHoldCondition_of_admitted admitted)
    context clock index script execution same holds

/-- The run theorem of the four constraint atoms together for {name}`runScriptFrom`. For every profile,
context in execution mode with the limits of the profile, clock, index, connection and statements with their
values: if the state of the connection satisfies {name}`SqlState.Holds` for {name}`Database.AdmittedWith`
{name}`Database.ConstraintAtoms` (its database, and its snapshot when a transaction is open), the state of the
connection of the run ({lit}`connection.state`) satisfies it. It has no hypothesis on the statements of the
script. Proof sketch: {name}`runScriptFrom_admittedWith` for {name}`constraintAtoms_statementKeeps`. -/
theorem runScriptFrom_constraintAtoms {profile : Profile} (context : ResolveContext) (clock : Option Clock)
    (index : Nat) {connection : Connection} (script : List (Syntax.Statement × List Value))
    (execution : context.mode = .execution) (same : context.profile.limits = profile.limits)
    (holds : connection.state.Holds (Database.AdmittedWith profile Database.ConstraintAtoms)) :
    (runScriptFrom context clock index connection script).connection.state.Holds
      (Database.AdmittedWith profile Database.ConstraintAtoms) :=
  runScriptFrom_admittedWith constraintAtoms_statementKeeps
    (fun _ statement admitted applied link => statement.atomsCondition_of_link admitted applied link)
    context clock index script execution same holds

end Belay.Sqlite.Model
