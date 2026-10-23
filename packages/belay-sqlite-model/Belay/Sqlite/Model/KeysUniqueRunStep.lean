import Belay.Sqlite.Model.KeysUniqueStatement
import Belay.Sqlite.Model.RunHolds

set_option doc.verso true

/-! The invariant of a run and the condition of a statement in a run for the atom "keys unique"
(ADR 0022, D3, slice 2): the database of the connection state, and its snapshot when a transaction
is open, satisfy {lit}`Database.KeysUnique`, and so does each database of an outcome. The steps are
the theorems of {lit}`RunHoldsStep` and {lit}`RunHolds` for the property
{lit}`Database.KeysUnique`. -/

namespace Belay.Sqlite.Model

/-- For the given state of a run: the database of the state satisfies
{name}`Database.KeysUnique`, and the snapshot satisfies it when the state has one. A state
without a snapshot requires nothing of the snapshot. -/
abbrev SqlState.KeysUnique (state : SqlState) : Prop := state.Holds Database.KeysUnique

/-- For the given outcome of a run, each database of it satisfies {name}`Database.KeysUnique`:

* the database of a success;
* the database of a failure;
* the persisted and the visible database of a pending outcome. -/
abbrev Outcome.KeysUnique (outcome : Outcome) : Prop := outcome.Holds Database.KeysUnique

/-- For the given database, the condition of a statement that a run reaches on the database
before it (owner decision of 2026-10-23 in the keys-unique status file):

* CREATE INDEX: the table of the index exists, and the index is supported for its width
  ({name}`CatalogIndex.supported`), as {name}`Catalog.supported` checks it;
* ADD COLUMN: {name}`Database.AddColumnCondition` of the target;
* DROP: {name}`Catalog.DropCondition` of the dropped positions;
* every other statement: nothing. -/
def Resolved.Statement.RunCondition (database : Database) : Resolved.Statement → Prop
  | .createIndex _ _ index =>
    ((database.catalog.tableAt index.table).any fun table => index.supported table.columns.length) = true
  | .addColumn target _ => database.AddColumnCondition target
  | .drop positions _ => database.catalog.DropCondition positions
  | .createTable .. | .createTrigger .. | .begin | .commit | .rollback | .insert .. | .update ..
  | .upsert .. | .delete .. | .prepareError _ | .query .. | .setting _ _ => True

/-- For every database and statement: if the statement meets its run condition
({name}`Resolved.Statement.RunCondition`), it meets the condition of the statement theorem
({name}`Resolved.Statement.KeysCondition`). The statement theorem does not use the condition of
CREATE INDEX. Proof sketch: ADD COLUMN and DROP have the same condition in both, and every other
statement has the condition {lean}`True` in the statement theorem. -/
theorem Resolved.Statement.keysCondition_of_runCondition {database : Database} :
    ∀ {statement : Resolved.Statement}, statement.RunCondition database → statement.KeysCondition database
  | .addColumn .., condition | .drop .., condition => condition
  | .createTable .., _ | .createIndex .., _ | .createTrigger .., _ | .begin, _ | .commit, _ | .rollback, _
  | .insert .., _ | .update .., _ | .upsert .., _ | .delete .., _ | .prepareError _, _ | .query .., _
  | .setting _ _, _ => trivial

/-- Whether a statement has no run condition: false for CREATE INDEX, ADD COLUMN and DROP, and
true for every other statement. For example, a script of CREATE TABLE and writes has no run
condition. -/
def Resolved.Statement.unconditioned : Resolved.Statement → Bool
  | .createIndex .. | .addColumn .. | .drop .. => false
  | .createTable .. | .createTrigger .. | .begin | .commit | .rollback | .insert .. | .update ..
  | .upsert .. | .delete .. | .prepareError _ | .query .. | .setting _ _ => true

/-- For every database and statement: if the statement has no run condition
({name}`Resolved.Statement.unconditioned`), it meets its run condition on the database. Proof
sketch: a case for each statement; CREATE INDEX, ADD COLUMN and DROP contradict the hypothesis,
and every other statement has the condition {lean}`True`. -/
theorem Resolved.Statement.runCondition_of_unconditioned {database : Database} :
    ∀ {statement : Resolved.Statement}, statement.unconditioned = true → statement.RunCondition database := by
  intro statement unconditioned
  cases statement <;> first | trivial | exact nomatch unconditioned

end Belay.Sqlite.Model
