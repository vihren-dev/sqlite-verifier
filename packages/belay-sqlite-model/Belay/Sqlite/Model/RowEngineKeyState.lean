import Belay.Sqlite.Model.RowEngineFacts
import Belay.Sqlite.Model.ForeignKeyPhases

set_option doc.verso true

/-! The invariant of the row engine for an atom with the facts of {lit}`TableFacts` (ADR 0022, D3,
slices 2 and 3): the database of each state that the engine reaches has the fact in every table,
for a running state and for the state that a FAIL or ROLLBACK stop carries. This module gives the
invariant, its laws over the steps of the {lit}`Except` monad, and the frame facts of a state.
The theorems of the engine take the fact as a parameter; "keys unique" and the atoms "not null",
"types fit" and "checks hold" are instances. -/

namespace Belay.Sqlite.Model

/-- For the given fact of a table, catalog and state: the database of the state over the catalog
({name}`KeyState.database`) has the fact in every table ({name}`Database.Every`). -/
def KeyState.Holds (fact : Catalog → Nat → Table → Prop) (catalog : Catalog) (state : KeyState) : Prop :=
  (state.database catalog).Every fact

/-- For the given fact, catalog and stop of the row engine: a stop with the FAIL or ROLLBACK
algorithm carries a state that satisfies {name}`KeyState.Holds`. A stop with an error of
the statement and an undescribed stop require nothing: they keep no state. -/
def KeyStop.Holds (fact : Catalog → Nat → Table → Prop) (catalog : Catalog) : KeyStop → Prop
  | .stopped _ state => state.Holds fact catalog
  | .error _ | .undescribed => True

/-- For the given properties of values and of stops, and a result: a success has a value with
the first property, and a stop has the second. -/
def ResultHolds {α} (good : α → Prop) (stopGood : KeyStop → Prop) : Except KeyStop α → Prop
  | .ok value => good value
  | .error stop => stopGood stop

/-- For every two properties of values, property of stops, result and continuation: if the
result holds the first property of values and the property of stops, and for each value with
the first property the result of the continuation holds the second property of values and the
property of stops, then their bind holds the second property of values and the property of
stops. Proof sketch: a stop passes through the bind. -/
theorem ResultHolds.bind {α β} {good : α → Prop} {next : β → Prop} {stopGood : KeyStop → Prop}
    {result : Except KeyStop α} {continuation : α → Except KeyStop β} (holds : ResultHolds good stopGood result)
    (step : ∀ value, good value → ResultHolds next stopGood (continuation value)) :
    ResultHolds next stopGood (result >>= continuation) := by
  cases result with
  | error stop => exact holds
  | ok value => exact step value holds

/-- For every two properties of values, property of stops, result and function: if the result
holds the first properties and the function maps each value with the first property to a value
with the second, the mapped result holds the second property and the stop property. Proof
sketch: a stop passes through the map. -/
theorem ResultHolds.map {α β} {good : α → Prop} {next : β → Prop} {stopGood : KeyStop → Prop}
    {result : Except KeyStop α} {function : α → β} (holds : ResultHolds good stopGood result)
    (maps : ∀ value, good value → next (function value)) : ResultHolds next stopGood (function <$> result) := by
  cases result with
  | error stop => exact holds
  | ok value => exact maps value holds

/-- For every property of values, property of stops, step function, list and start value: if the
start value has the property and each step from a value with the property holds both
properties, the fold of the steps over the list ({lit}`List.foldlM`) holds them. Proof sketch:
induction on the list with {name}`ResultHolds.bind`. -/
theorem ResultHolds.foldlM {α β} {good : β → Prop} {stopGood : KeyStop → Prop} {step : β → α → Except KeyStop β}
    (steps : ∀ value element, good value → ResultHolds good stopGood (step value element)) :
    ∀ (list : List α) (start : β), good start → ResultHolds good stopGood (list.foldlM step start)
  | [], start, holds => holds
  | element :: rest, start, holds => by
    rw [List.foldlM_cons]
    exact ResultHolds.bind (steps start element holds) fun value next => ResultHolds.foldlM steps rest value next

/-- For every two properties of values and property of stops: if the first property implies the
second, and the result holds the first, it holds the second. Proof sketch: case analysis on the
result. -/
theorem ResultHolds.mono {α} {good better : α → Prop} {stopGood : KeyStop → Prop} {result : Except KeyStop α}
    (holds : ResultHolds good stopGood result) (implies : ∀ value, good value → better value) :
    ResultHolds better stopGood result := by
  cases result with
  | error stop => exact holds
  | ok value => exact implies value holds

/-- For every two properties of values, two properties of stops and result: if the result holds
the first properties, and each first property implies the second, it holds the second. Proof
sketch: case analysis on the result. -/
theorem ResultHolds.imp {α} {good better : α → Prop} {stopGood stopBetter : KeyStop → Prop} {result : Except KeyStop α}
    (holds : ResultHolds good stopGood result) (implies : ∀ value, good value → better value)
    (stops : ∀ stop, stopGood stop → stopBetter stop) : ResultHolds better stopBetter result := by
  cases result with
  | error stop => exact stops stop holds
  | ok value => exact implies value holds

/-- For every fact, catalog and two states with the same rows: if the second satisfies
{name}`KeyState.Holds`, the first does. Proof sketch: the database of a state reads only
its rows. -/
theorem KeyState.holds_of_rows {fact : Catalog → Nat → Table → Prop} {catalog : Catalog} {state other : KeyState}
    (rows : state.rows = other.rows) (holds : other.Holds fact catalog) : state.Holds fact catalog := by
  unfold KeyState.Holds KeyState.database at *
  rw [rows]
  exact holds

/-- For every fact, catalog, start state and result: if the start state satisfies
{name}`KeyState.Holds`, and the result is a state with the rows of the start state or an
undescribed stop, the result satisfies the invariant: each success satisfies
{name}`KeyState.Holds` and each stop {name}`KeyStop.Holds`. The foreign-key steps of a
row have such results. Proof sketch: the database of a state reads only its rows. -/
theorem ResultHolds.holds_of_rows {fact : Catalog → Nat → Table → Prop} {catalog : Catalog} {start : KeyState}
    (holds : start.Holds fact catalog) {result : Except KeyStop KeyState}
    (kept : ResultHolds (fun state => state.rows = start.rows) (· = .undescribed) result) :
    ResultHolds (KeyState.Holds fact catalog) (KeyStop.Holds fact catalog) result := by
  cases result with
  | error stop => cases kept; trivial
  | ok state => exact KeyState.holds_of_rows kept holds

/-- For every fact, catalog, state, position and change of rows: if the state satisfies
{name}`KeyState.Holds`, and the table at the position (when there is one) with the changed
rows has the fact for the position, the state after {name}`KeyState.changeRows` satisfies
{name}`KeyState.Holds`. A position without a table requires nothing. Proof sketch: the database
of the changed state is the database after {name}`Database.setRows`
({name}`Database.Every.setRows`); without a table, every table of the database is the same
({name}`Database.table_setRows_other`). -/
theorem KeyState.holds_changeRows {fact : Catalog → Nat → Table → Prop} {catalog : Catalog} {state : KeyState}
    (holds : state.Holds fact catalog) {position : Nat} {change : List Row → List Row}
    (stored : ∀ table, (state.database catalog).table position = some table →
      fact catalog position { table with rows := change (state.rows.getD position []) }) :
    (state.changeRows position change).Holds fact catalog := by
  have setRows : (state.changeRows position change).database catalog =
      (state.database catalog).setRows position (change (state.rows.getD position [])) := rfl
  unfold KeyState.Holds
  rw [setRows]
  cases found : (state.database catalog).table position with
  | some table => exact Database.Every.setRows holds found (stored table found)
  | none =>
    intro other table present
    by_cases same : other = position
    · subst same
      simp [Database.table, Database.setRows, KeyState.database] at found present
      simp_all
    · rw [Database.table_setRows_other _ _ same] at present
      exact holds other table present

/-- For every catalog, state, position and table: if the database of the state has the table at
the position, the rows of the table are the rows of the state at the position. Proof sketch: the
definition of {name}`Database.table`. -/
theorem KeyState.table_rows {catalog : Catalog} {state : KeyState} {position : Nat} {table : Table}
    (found : (state.database catalog).table position = some table) : table.rows = state.rows.getD position [] := by
  obtain ⟨_, _, same⟩ := Option.map_eq_some_iff.mp found
  rw [← same]
  rfl

/-- For every catalog, state, position and table: if the database of the state has the table at
the position, the catalog has the table's entry there. Proof sketch: the definition of
{name}`Database.table`. -/
theorem KeyState.table_shape {catalog : Catalog} {state : KeyState} {position : Nat} {table : Table}
    (found : (state.database catalog).table position = some table) : catalog.tableAt position = some table.shape := by
  obtain ⟨_, atShape, same⟩ := Option.map_eq_some_iff.mp found
  rw [← same]
  exact atShape

/-- For every fact with the facts of {name}`TableFacts`, catalog, state, position and change of
rows that gives a sublist of each list of rows: if the state satisfies {name}`KeyState.Holds`, the
state after {name}`KeyState.changeRows` satisfies it. A DELETE of a row makes such a change. Proof
sketch: {name}`KeyState.holds_changeRows` with {name}`TableFacts.sublist`; the table keeps its
entry. -/
theorem KeyState.holds_changeRows_sublist {fact : Catalog → Nat → Table → Prop} (facts : TableFacts fact)
    {catalog : Catalog} {state : KeyState} (holds : state.Holds fact catalog) {position : Nat}
    {change : List Row → List Row} (sublist : ∀ rows, (change rows).Sublist rows) :
    (state.changeRows position change).Holds fact catalog :=
  KeyState.holds_changeRows holds fun table found =>
    facts.sublist catalog position table _ (holds position table found) rfl
      (by rw [KeyState.table_rows found]; exact sublist _)

/-- For every fact and database: if every table of the database has the fact, the state
{lit}`{ rows := database.rows }` (the rows of the database, and the default value of each other
field) satisfies {name}`KeyState.Holds` over the catalog of the database. The row engine starts
from this state. Proof sketch: the database of the state is the database. -/
theorem KeyState.holds_start {fact : Catalog → Nat → Table → Prop} {database : Database}
    (holds : database.Every fact) : ({ rows := database.rows } : KeyState).Holds fact database.catalog := holds

end Belay.Sqlite.Model
