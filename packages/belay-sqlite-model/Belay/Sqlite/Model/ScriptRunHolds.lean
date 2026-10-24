import Belay.Sqlite.Model.RunHolds
import Belay.Sqlite.Model.ScriptRun

set_option doc.verso true

/-! The run theorem for {lit}`runScriptFrom`, the run of the surface, for every property of
databases (ADR 0022, D3, slices 2 and 3): the connection at the end of the run has the property in
its database and its snapshot, when the statement theorem of the property holds and each statement
that the run resolves meets its condition. Slice 4 proves the resolver facts that give the
conditions and removes the hypothesis from the theorems of the atoms. -/

namespace Belay.Sqlite.Model

/-- For the given condition of statements on a database, context, clock, index, connection and
statements with their values, each statement that {name}`runScriptFrom` resolves meets the
condition on the database of the connection before it:

* the empty list requires nothing;
* a list with a first statement requires, for each resolved statement and state that
  {name}`resolveStatement` gives for the first statement over the connection, the condition of
  the resolved statement on the database of the connection; and, when
  {name}`runScriptStep` continues with a next connection, the conditions of the rest from the
  next index and the next connection. A statement at which the run ends requires nothing of the
  rest, and a statement that does not resolve requires no condition. -/
def ScriptConditionsWith (condition : Resolved.Statement → Database → Prop) (context : ResolveContext)
    (clock : Option Clock) (index : Nat) (connection : Connection) :
    List (Syntax.Statement × List Value) → Prop
  | [] => True
  | (statement, parameters) :: rest =>
    (∀ resolved after, resolveStatement context connection.resolveState statement = .ok (resolved, after) →
      condition resolved connection.state.database) ∧
      match runScriptStep context clock index connection statement parameters with
      | .ended _ => True
      | .continued _ next => ScriptConditionsWith condition context clock (index + 1) next rest

variable {property : Database → Prop} {condition : Resolved.Statement → Database → Prop}

/-- For every property, connection, resolution state, counts and transition: if the transition satisfies
{name}`SqlTransition.Holds`, the state of the connection after the transition
({name}`Connection.afterStep`) satisfies {name}`SqlState.Holds`. Proof sketch: a transition that
continues gives its state; a success or a failure leaves the connection without a snapshot; a
pending outcome keeps its persisted database as the snapshot. -/
theorem Connection.afterStep_holds (connection : Connection) (after : ResolveState) (counts : Counts) :
    ∀ {transition : SqlTransition}, transition.Holds property →
      (connection.afterStep after counts transition).state.Holds property
  | .next _, holds => holds
  | .halt (.success _), holds | .halt (.failure ..), holds => ⟨holds, fun _ same => nomatch same⟩
  | .halt (.pending ..), holds => ⟨holds.2, fun _ same => Option.some.inj same ▸ holds.1⟩

/-- For every property, condition, context, clock, index, connection, statement and list of values:
if the statement theorem holds ({name}`StatementKeeps`), the state of the connection satisfies
{name}`SqlState.Holds`, each statement that {name}`resolveStatement` gives for the statement meets
the condition on the database of the connection, and {name}`runScriptStep` continues with a next
connection, then the state of the next connection satisfies {name}`SqlState.Holds`. Proof sketch:
the step runs the resolved statement and advances with its effect ({name}`advanceWith_holds` of the
statement theorem, {name}`SqlTransition.counted_holds`), then {name}`Connection.afterStep_holds`. -/
theorem runScriptStep_holds (keeps : StatementKeeps property condition) (context : ResolveContext)
    (clock : Option Clock) (index : Nat) {connection : Connection} (holds : connection.state.Holds property)
    (statement : Syntax.Statement) (parameters : List Value)
    (met : ∀ resolved after, resolveStatement context connection.resolveState statement = .ok (resolved, after) →
      condition resolved connection.state.database)
    {output : Output} {next : Connection}
    (continued : runScriptStep context clock index connection statement parameters = .continued output next) :
    next.state.Holds property := by
  unfold runScriptStep runScriptStepWith ranScriptStep at continued
  split at continued
  · nomatch continued
  · rename_i resolved after resolvedEq
    split at continued
    · nomatch continued
    · rename_i value _
      split at continued
      · nomatch continued
      · dsimp only at continued
        split at continued
        · nomatch continued
        · split at continued
          · nomatch continued
          all_goals
            injection continued with _ same
            subst same
            exact Connection.afterStep_holds connection _ _ (SqlTransition.counted_holds _ (advanceWith_holds index resolved holds
              (keeps value _ parameters resolved _ holds.1 (met resolved after resolvedEq))))

/-- The run theorem of {name}`runScriptFrom`, for every property and condition. For every context,
clock, index, connection and statements with their values: if the statement theorem holds
({name}`StatementKeeps`), the state of the connection satisfies {name}`SqlState.Holds` (its
database, and its snapshot when a transaction is open) and the statements meet
{name}`ScriptConditionsWith` from the index and the connection, the state of the connection of the
run ({lit}`connection.state`) satisfies {name}`SqlState.Holds`. Proof sketch: induction on the
statements with {name}`runScriptStep_holds`; a run that ends keeps the connection. -/
theorem runScriptFrom_holds (keeps : StatementKeeps property condition) (context : ResolveContext)
    (clock : Option Clock) :
    ∀ (index : Nat) {connection : Connection} (script : List (Syntax.Statement × List Value)),
      connection.state.Holds property → ScriptConditionsWith condition context clock index connection script →
        (runScriptFrom context clock index connection script).connection.state.Holds property
  | _, _, [], holds, _ => holds
  | index, connection, (statement, parameters) :: rest, holds, conditions => by
    have step : ∀ output next, runScriptStep context clock index connection statement parameters = .continued output next →
        next.state.Holds property := fun _ _ =>
      runScriptStep_holds keeps context clock index holds statement parameters conditions.1
    have later := conditions.2
    unfold runScriptFrom
    revert step later
    cases runScriptStep context clock index connection statement parameters with
    | ended _ => exact fun _ _ => holds
    | continued output next =>
      exact fun step later => runScriptFrom_holds keeps context clock (index + 1) rest (step output next rfl) later

end Belay.Sqlite.Model
