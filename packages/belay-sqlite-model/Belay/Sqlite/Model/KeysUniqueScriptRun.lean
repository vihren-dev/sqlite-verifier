import Belay.Sqlite.Model.KeysUniqueRuns
import Belay.Sqlite.Model.ScriptRunHolds

set_option doc.verso true

/-! The run theorem of the atom "keys unique" for {lit}`runScriptFrom`, the run of the surface
(ADR 0022, D3, slice 2): the connection at the end of the run keeps the keys unique in its
database and its snapshot, when each statement that the run resolves meets its condition. It is
the run theorem of {lit}`ScriptRunHolds` for the statement theorem of the atom. Slice 4 proves the
resolver facts that give the condition and removes the hypothesis from this theorem. -/

namespace Belay.Sqlite.Model

/-- For the given context, clock, index, connection and statements with their values, each
statement that {name}`runScriptFrom` resolves meets its run condition
({name}`Resolved.Statement.RunCondition`) on the database of the connection before it:

* the empty list requires nothing;
* a list with a first statement requires, for each resolved statement and state that
  {name}`resolveStatement` gives for the first statement over the connection, the condition of
  the resolved statement on the database of the connection; and, when
  {name}`runScriptStep` continues with a next connection, the conditions of the rest from the
  next index and the next connection. A statement at which the run ends requires nothing of the
  rest, and a statement that does not resolve requires no condition. -/
abbrev ScriptConditions (context : ResolveContext) (clock : Option Clock) (index : Nat) (connection : Connection)
    (script : List (Syntax.Statement × List Value)) : Prop :=
  ScriptConditionsWith (fun statement database => statement.RunCondition database) context clock index connection script

/-- The run theorem of {name}`runScriptFrom`. For every context, clock, index, connection and
statements with their values: if the state of the connection satisfies
{name}`SqlState.KeysUnique` (its database, and its snapshot when a transaction is open) and the
statements meet {name}`ScriptConditions` from the index and the connection, the state of the
connection of the run ({lit}`connection.state`) satisfies {name}`SqlState.KeysUnique`. Proof
sketch: {name}`runScriptFrom_holds` for {name}`keysUnique_statementKeeps`. -/
theorem runScriptFrom_keysUnique (context : ResolveContext) (clock : Option Clock) (index : Nat)
    {connection : Connection} (script : List (Syntax.Statement × List Value))
    (unique : connection.state.KeysUnique) (conditions : ScriptConditions context clock index connection script) :
    (runScriptFrom context clock index connection script).connection.state.KeysUnique :=
  runScriptFrom_holds keysUnique_statementKeeps context clock index script unique conditions

end Belay.Sqlite.Model
