import Belay.Sqlite.Model.ScriptRunValid
import Belay.Sqlite.Model.AdmittedSqlRunsRows
import Belay.Sqlite.Model.ResolveStatementFacts
import Belay.Sqlite.Model.AdmittedAtomsSchemaExamples
import Belay.Sqlite.Model.AdmittedAtomsCounterExamples
import Belay.Sqlite.Model.AdmittedAtomsEngineExamples
import Belay.Sqlite.Model.ForeignKeyExamples

set_option doc.verso true

/-! Examples of the run theorems of the Admitted atoms (ADR 0022, slice 4, part 3), each checked by the
kernel: the corollary {lit}`runScriptFrom_valid` applied to a script with CREATE INDEX, ADD COLUMN, DROP TABLE
of a table with an index and a trigger, a DELETE that cascades and a ROLLBACK, with no hypothesis on the
statements; the facts of the resolver on concrete statements; the conditions that stay in the theorems of
{lit}`runSqlFrom` and {lit}`runSql`, each with a run that breaks the atom when the condition fails. -/

namespace Belay.Sqlite.Model.AdmittedRunsExamples

open Belay.Sqlite.Model Syntax Resolution.Examples
open Belay.Sqlite.Model.ForeignKeyExamples (keysOn deleteOne)
open Belay.Sqlite.Model.AdmittedAtomsSchemaExamples (createT term triggerOnT)
open Belay.Sqlite.Model.AdmittedAtomsExamples (indexedCatalog)

/-- {lit}`CREATE UNIQUE INDEX ia ON t(a)`. -/
def uniqueIndex : Syntax.Statement := .createIndex (name! "ia") true (name! "t") [term (name! "a")] none

/-- {lit}`ALTER TABLE t ADD COLUMN c INTEGER DEFAULT 5`. -/
def addFive : Syntax.Statement :=
  .addColumn (name! "t") { name := name! "c", declaredType := some "INTEGER", constraints := [.default (.numeric "5") "5"] }

/-- With foreign keys on: the tables {lit}`p` and {lit}`c` of {lit}`ForeignKeyExamples` with their rows
({lit}`ON DELETE CASCADE`), then {lit}`CREATE TABLE t(a INTEGER, b TEXT)`, one row of {lit}`t`, a unique index
and a trigger on {lit}`t`, ADD COLUMN, {lit}`BEGIN`, the DELETE of the row 1 of {lit}`p`, which deletes the row
of {lit}`c`, {lit}`DROP TABLE t` (with its index and its trigger), and {lit}`ROLLBACK`. -/
def mixedSyntax : List Syntax.Statement :=
  ForeignKeyExamples.schema .cascade .noAction ++
    [createT, .insert (name! "t") none [[.numeric "1", .numeric "2"]] [], uniqueIndex, triggerOnT, addFive,
      .begin, deleteOne, .dropTable (name! "t") false, .rollback]

/-- The context of the run: the profile with foreign keys on, in execution mode. -/
def mixedContext : ResolveContext := { profile := keysOn, mode := .execution }

/-- A new connection with foreign keys on. -/
def start : Connection := { state := { database := {} }, foreignKeys := true }

/-- The run of {name}`mixedSyntax` from {name}`start`, without values and without a clock. -/
def mixedRun : ScriptRun := runScriptFrom mixedContext none 0 start (bindValues mixedSyntax [])

/-- Whether an output is an error or the end of the run. -/
def Output.failed : Output → Bool
  | .error _ | .unmodeled _ => true
  | .rows _ | .done _ | .oneOf _ => false

-- The run gives 13 outputs and none fails. It ends with the five objects of the catalog (the tables `p`, `c`
-- and `t`, the index and the trigger), because ROLLBACK restores the table `t` that DROP TABLE dropped, and
-- no transaction is open.
#guard mixedRun.outputs.length == 13 && !mixedRun.outputs.any Output.failed &&
  mixedRun.connection.state.database.catalog.length == 5 && mixedRun.connection.state.snapshot.isNone

/-- The corollary applied to {name}`mixedSyntax`: the database of the run is valid, and so is the snapshot
when a transaction is open. The proof has no fact about CREATE INDEX, ADD COLUMN, DROP TABLE, the cascade or
ROLLBACK: the theorem needs only the start state, the mode and the limits. -/
theorem mixedRun_valid : mixedRun.connection.state.Holds (Database.Valid keysOn) :=
  runScriptFrom_valid mixedContext none 0 (bindValues mixedSyntax []) rfl rfl
    ⟨Database.valid_empty keysOn, fun _ same => nomatch same⟩

/-- The theorem of "rows aliased" applied to {name}`mixedSyntax`: the database of the run satisfies
{name}`Database.RowsAliased` and has a valid catalog under the limits of the profile, and so does the snapshot
when a transaction is open. The theorem has no hypothesis on the statements either. -/
theorem mixedRun_rowsAliased : mixedRun.connection.state.Holds (Database.RowsAliasedSupported keysOn.limits) :=
  runScriptFrom_rowsAliased mixedContext none 0 (bindValues mixedSyntax []) rfl rfl
    ⟨⟨(Database.valid_empty keysOn).admitted.rowsAliased, (Database.valid_empty keysOn).admitted.catalogSupported⟩, fun _ same => nomatch same⟩

end Belay.Sqlite.Model.AdmittedRunsExamples
