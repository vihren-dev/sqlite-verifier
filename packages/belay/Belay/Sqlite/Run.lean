import Belay.Sqlite.Script
import Belay.Sqlite.Database

set_option doc.verso true

/-! The surface's runs of scripts on a connection (ADR 0017, D3, amended 2026-10-22; ADR 0022, D5,
amended): {lit}`Database.Raw.run` runs the statements of a script one at a time, as an
application sends them, with the model's run that resolves each statement when it runs and
continues after an error, without the check of the database at its end. {lit}`ProgramRun.lean`
runs programs and scripts on a {lit}`Database`, with the check, and {lit}`RunLaws.lean` states
how runs compose. -/

namespace Belay.Sqlite

export Belay.Sqlite.Model (Output Output.rows Output.done Output.error Output.oneOf Output.unmodeled
  Output.endsRun Output.isError Connection ScriptRun ScriptRun.ended ScriptRun.andThen)

/-- The context in which the surface resolves the statements of a run: the pinned profile
({name}`Profile.pinned`), with statements that run. -/
def runContext : Belay.Sqlite.Model.ResolveContext := { profile := Profile.pinned, mode := .execution }

/-- The model's run of the script on the connection, each statement with its values
({name}`Belay.Sqlite.Model.runScriptFrom`), from the first statement, without a clock and
without a check of the database at its end. A statement that reads the clock ends the run. -/
def Script.runOn (connection : Connection) (script : Script) : ScriptRun :=
  Belay.Sqlite.Model.runScriptFrom runContext none 0 connection script.statements

/-- The idle connection to the plain database: no open transaction, foreign keys off, as a new
SQLite connection, and the clock assignment of 0 at every position, which the run carries
without a change. -/
def Database.Raw.connection (raw : Database.Raw) : Connection := { state := { database := raw } }

/-- Run the script on the plain database ({name}`Script.runOn` of
{name}`Database.Raw.connection`): the model's result that the run reached, without the check
that the database at its end is valid. -/
def Database.Raw.run (raw : Database.Raw) (script : Script) : ScriptRun := script.runOn raw.connection

end Belay.Sqlite
