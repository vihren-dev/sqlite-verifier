import Belay.Sqlite.Model.ScriptRunApplied
import Belay.Sqlite.Model.ScriptRunDerived

set_option doc.verso true

/-! The run theorems of the atoms "catalog supported", "rows shaped", "rowids distinct" and "rowids in range"
for {lit}`runScriptFrom`, the run of the surface (ADR 0022, D3, slice 4). A statement that
{lit}`runScriptFrom` runs has passed the support check, and the resolver gives the condition of "catalog
supported" (the catalog after the statement is valid), so the theorems have no hypothesis on the statements
of the script. -/

namespace Belay.Sqlite.Model

/-- The run theorem of "catalog supported" for {name}`runScriptFrom`, the run of the surface. For every
limits, context, clock, index, connection and statements with their values: if the context is in execution
mode and has the given limits ({lit}`context.profile.limits = limits`), and the state of the connection
satisfies {name}`SqlState.Holds` for {name}`Database.CatalogSupported` (its database, and its snapshot when
a transaction is open), the state of the connection of the run ({lit}`connection.state`) satisfies it. It
has no hypothesis on the statements of the script: the resolver gives the condition of each statement
({name}`resolveStatement_appliedValid`). Proof sketch: {name}`runScriptFrom_holds_derived` for
{name}`catalogSupported_statementKeeps`. -/
theorem runScriptFrom_catalogSupported {limits : Limits} (context : ResolveContext) (clock : Option Clock) (index : Nat)
    {connection : Connection} (script : List (Syntax.Statement × List Value))
    (execution : context.mode = .execution) (same : context.profile.limits = limits)
    (holds : connection.state.Holds (Database.CatalogSupported limits)) :
    (runScriptFrom context clock index connection script).connection.state.Holds (Database.CatalogSupported limits) :=
  runScriptFrom_holds_derived (catalogSupported_statementKeeps limits) context clock
    (fun _ _ _ _ keep ok => resolveStatement_appliedValid context execution same keep ok) index script holds

/-- The run theorem of "rows shaped" for {name}`runScriptFrom`, the run of the surface. For every context,
clock, index, connection and statements with their values: if the state of the connection satisfies
{name}`SqlState.Holds` for {name}`Database.RowsShaped` (its database, and its snapshot when a transaction is
open), the state of the connection of the run ({lit}`connection.state`) satisfies it. It has no hypothesis
on the statements of the script, and the statement theorem needs no condition. Proof sketch:
{name}`runScriptFrom_holds_derived` for {name}`rowsShaped_statementKeeps`. -/
theorem runScriptFrom_rowsShaped (context : ResolveContext) (clock : Option Clock) (index : Nat)
    {connection : Connection} (script : List (Syntax.Statement × List Value))
    (holds : connection.state.Holds Database.RowsShaped) :
    (runScriptFrom context clock index connection script).connection.state.Holds Database.RowsShaped :=
  runScriptFrom_holds_derived (rowsShaped_statementKeeps) context clock (fun _ _ _ _ _ _ => trivial) index script holds

/-- The run theorem of "rowids distinct" for {name}`runScriptFrom`, the run of the surface. For every
context, clock, index, connection and statements with their values: if the state of the connection satisfies
{name}`SqlState.Holds` for {name}`Database.RowidsDistinct` (its database, and its snapshot when a
transaction is open), the state of the connection of the run ({lit}`connection.state`) satisfies it. It has
no hypothesis on the statements of the script, and the statement theorem needs no condition. Proof sketch:
{name}`runScriptFrom_holds_derived` for {name}`rowidsDistinct_statementKeeps`. -/
theorem runScriptFrom_rowidsDistinct (context : ResolveContext) (clock : Option Clock) (index : Nat)
    {connection : Connection} (script : List (Syntax.Statement × List Value))
    (holds : connection.state.Holds Database.RowidsDistinct) :
    (runScriptFrom context clock index connection script).connection.state.Holds Database.RowidsDistinct :=
  runScriptFrom_holds_derived (rowidsDistinct_statementKeeps) context clock (fun _ _ _ _ _ _ => trivial) index script holds

/-- The run theorem of "rowids in range" for {name}`runScriptFrom`, the run of the surface. For every
context, clock, index, connection and statements with their values: if the state of the connection satisfies
{name}`SqlState.Holds` for {name}`Database.RowidsInRange` (its database, and its snapshot when a transaction
is open), the state of the connection of the run ({lit}`connection.state`) satisfies it. It has no
hypothesis on the statements of the script, and the statement theorem needs no condition. Proof sketch:
{name}`runScriptFrom_holds_derived` for {name}`rowidsInRange_statementKeeps`. -/
theorem runScriptFrom_rowidsInRange (context : ResolveContext) (clock : Option Clock) (index : Nat)
    {connection : Connection} (script : List (Syntax.Statement × List Value))
    (holds : connection.state.Holds Database.RowidsInRange) :
    (runScriptFrom context clock index connection script).connection.state.Holds Database.RowidsInRange :=
  runScriptFrom_holds_derived (rowidsInRange_statementKeeps) context clock (fun _ _ _ _ _ _ => trivial) index script holds

end Belay.Sqlite.Model
