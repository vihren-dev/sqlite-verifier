import Belay.Sqlite.Model.ScriptRunApplied
import Belay.Sqlite.Model.ScriptRunDerived

set_option doc.verso true

/-! The run theorems of the atoms "rows wide", "rows stored" and "rows aliased", and of all seven atoms
together, for {lit}`runScriptFrom`, the run of the surface (ADR 0022, D3, slice 4). They have no hypothesis
on the statements of the script. The theorem of an atom lists the atoms that its statement theorem needs
(decision 2 of the status file). -/

namespace Belay.Sqlite.Model

/-- The run theorem of "rows wide" for {name}`runScriptFrom`, the run of the surface. For every context,
clock, index, connection and statements with their values: if the state of the connection satisfies
{name}`SqlState.Holds` for {name}`Database.RowsWide` (its database, and its snapshot when a transaction is
open), the state of the connection of the run ({lit}`connection.state`) satisfies it. It has no hypothesis
on the statements of the script, and the statement theorem needs no condition. Proof sketch:
{name}`runScriptFrom_holds_derived` for {name}`rowsWide_statementKeeps`. -/
theorem runScriptFrom_rowsWide (context : ResolveContext) (clock : Option Clock) (index : Nat)
    {connection : Connection} (script : List (Syntax.Statement × List Value))
    (holds : connection.state.Holds Database.RowsWide) :
    (runScriptFrom context clock index connection script).connection.state.Holds Database.RowsWide :=
  runScriptFrom_holds_derived (rowsWide_statementKeeps) context clock (fun _ _ _ _ _ _ => trivial) index script holds

/-- The run theorem of "rows stored" for {name}`runScriptFrom`, the run of the surface. It lists "rows wide"
(decision 2 of the status file). For every context, clock, index, connection and statements with their
values: if the state of the connection satisfies {name}`SqlState.Holds` for {name}`Database.RowsStoredWide`
(its database, and its snapshot when a transaction is open), the state of the connection of the run
({lit}`connection.state`) satisfies it. It has no hypothesis on the statements of the script, and the
statement theorem needs no condition. Proof sketch: {name}`runScriptFrom_holds_derived` for
{name}`rowsStored_statementKeeps`. -/
theorem runScriptFrom_rowsStored (context : ResolveContext) (clock : Option Clock) (index : Nat)
    {connection : Connection} (script : List (Syntax.Statement × List Value))
    (holds : connection.state.Holds Database.RowsStoredWide) :
    (runScriptFrom context clock index connection script).connection.state.Holds Database.RowsStoredWide :=
  runScriptFrom_holds_derived (rowsStored_statementKeeps) context clock (fun _ _ _ _ _ _ => trivial) index script holds

/-- The run theorem of "rows aliased" for {name}`runScriptFrom`, the run of the surface. It lists "catalog
supported" (decision 2 of the status file). For every limits, context, clock, index, connection and
statements with their values: if the context is in execution mode and has the given limits
({lit}`context.profile.limits = limits`), and the state of the connection satisfies {name}`SqlState.Holds`
for {name}`Database.RowsAliasedSupported` (its database, and its snapshot when a transaction is open), the
state of the connection of the run ({lit}`connection.state`) satisfies it. It has no hypothesis on the
statements of the script: the resolver gives the condition of each statement
({name}`resolveStatement_appliedValid`). Proof sketch: {name}`runScriptFrom_holds_derived` for
{name}`rowsAliased_statementKeeps`. -/
theorem runScriptFrom_rowsAliased {limits : Limits} (context : ResolveContext) (clock : Option Clock) (index : Nat)
    {connection : Connection} (script : List (Syntax.Statement × List Value))
    (execution : context.mode = .execution) (same : context.profile.limits = limits)
    (holds : connection.state.Holds (Database.RowsAliasedSupported limits)) :
    (runScriptFrom context clock index connection script).connection.state.Holds (Database.RowsAliasedSupported limits) :=
  runScriptFrom_holds_derived (rowsAliased_statementKeeps limits) context clock
    (fun _ _ _ _ keep ok => resolveStatement_appliedValid context execution same
      (keep.mono (fun _ holds => holds.2)) ok) index script holds

/-- The run theorem of "all seven atoms" for {name}`runScriptFrom`, the run of the surface. It is the
conjunction of the seven atoms. For every profile, context, clock, index, connection and statements with
their values: if the context is in execution mode and has the limits of the profile
({lit}`context.profile.limits = profile.limits`), and the state of the connection satisfies
{name}`SqlState.Holds` for {name}`Database.Admitted` (its database, and its snapshot when a transaction is
open), the state of the connection of the run ({lit}`connection.state`) satisfies it. It has no hypothesis
on the statements of the script: the resolver gives the condition of each statement
({name}`resolveStatement_appliedValid`). Proof sketch: {name}`runScriptFrom_holds_derived` for
{name}`admitted_statementKeeps`. -/
theorem runScriptFrom_admitted {profile : Profile} (context : ResolveContext) (clock : Option Clock) (index : Nat)
    {connection : Connection} (script : List (Syntax.Statement × List Value))
    (execution : context.mode = .execution) (same : context.profile.limits = profile.limits)
    (holds : connection.state.Holds (Database.Admitted profile)) :
    (runScriptFrom context clock index connection script).connection.state.Holds (Database.Admitted profile) :=
  runScriptFrom_holds_derived (admitted_statementKeeps profile) context clock
    (fun _ _ _ _ keep ok => resolveStatement_appliedValid context execution same
      (keep.mono (fun _ holds => holds.catalogSupported)) ok) index script holds

end Belay.Sqlite.Model
