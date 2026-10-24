import Belay.Sqlite.Model.RowEngineFacts
import Belay.Sqlite.Model.ForeignKeyPhases

set_option doc.verso true

/-! The invariant of the row engine for a property of databases with the laws of {lit}`WriteLaws`
(ADR 0022, D3, slices 2, 3 and 4): the database of each state that the engine reaches has the
property, for a running state and for the state that a FAIL or ROLLBACK stop carries. This module
gives the invariant, its laws over the steps of the {lit}`Except` monad, and the frame facts of a
state. The theorems of the engine take the property as a parameter; "keys unique", the atoms "not
null", "types fit" and "checks hold", "rowids distinct", "rows shaped" and "catalog supported" are
instances. -/

namespace Belay.Sqlite.Model

/-- For the given property of databases, catalog and state: the database of the state over the catalog
({name}`KeyState.database`) has the property. -/
def KeyState.Holds (invariant : Database → Prop) (catalog : Catalog) (state : KeyState) : Prop :=
  invariant (state.database catalog)

/-- For the given invariant, catalog and stop of the row engine: a stop with the FAIL or ROLLBACK
algorithm carries a state that satisfies {name}`KeyState.Holds`. A stop with an error of
the statement and an undescribed stop require nothing. The error stop carries the state of the
failure for its counts (ADR 0024, D2), but it keeps no rows, so the invariant does not constrain
that state. -/
def KeyStop.Holds (invariant : Database → Prop) (catalog : Catalog) : KeyStop → Prop
  | .stopped _ state => state.Holds invariant catalog
  | .error _ _ | .undescribed => True

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

/-- For every invariant, catalog and two states with the same rows: if the second satisfies
{name}`KeyState.Holds`, the first does. Proof sketch: the database of a state reads only
its rows. -/
theorem KeyState.holds_of_rows {invariant : Database → Prop} {catalog : Catalog} {state other : KeyState}
    (rows : state.rows = other.rows) (holds : other.Holds invariant catalog) : state.Holds invariant catalog := by
  unfold KeyState.Holds KeyState.database at *
  rw [rows]
  exact holds

/-- For every invariant, catalog, start state and result: if the start state satisfies
{name}`KeyState.Holds`, and the result is a state with the rows of the start state or an
undescribed stop, the result satisfies the invariant: each success satisfies
{name}`KeyState.Holds` and each stop {name}`KeyStop.Holds`. The foreign-key steps of a
row have such results. Proof sketch: the database of a state reads only its rows. -/
theorem ResultHolds.holds_of_rows {invariant : Database → Prop} {catalog : Catalog} {start : KeyState}
    (holds : start.Holds invariant catalog) {result : Except KeyStop KeyState}
    (kept : ResultHolds (fun state => state.rows = start.rows) (· = .undescribed) result) :
    ResultHolds (KeyState.Holds invariant catalog) (KeyStop.Holds invariant catalog) result := by
  cases result with
  | error stop => cases kept; trivial
  | ok state => exact KeyState.holds_of_rows kept holds

/-- For every catalog, state, position and table: if the database of the state has the table at
the position, the rows of the table are the rows of the state at the position. Proof sketch: the
definition of {name}`Database.table`. -/
theorem KeyState.table_rows {catalog : Catalog} {state : KeyState} {position : Nat} {table : Table}
    (found : (state.database catalog).table position = some table) : table.rows = state.rows.getD position [] := by
  obtain ⟨_, _, same⟩ := Option.map_eq_some_iff.mp found
  rw [← same]
  rfl

/-- For every invariant with {name}`WriteLaws`, catalog, state, position, change of rows and table: if
the state satisfies {name}`KeyState.Holds`, the database of the state has the table at the position, and
the table with the changed rows passes the checks of a write ({name}`LiteralData.constraints` with the
unique keys of the position, and {name}`LiteralData.rowidsDistinct`), and each changed row is a row at the
position or is admitted ({name}`LiteralData.rowAdmitted`), the state after
{name}`KeyState.changeRows` satisfies {name}`KeyState.Holds`. Proof sketch: the database of the changed
state is the database after {name}`Database.setRows`, which is the write of {name}`WriteLaws`. -/
theorem KeyState.holds_write {invariant : Database → Prop} (laws : WriteLaws invariant) {catalog : Catalog}
    {state : KeyState} (holds : state.Holds invariant catalog) {position : Nat} {change : List Row → List Row}
    {table : Table} (found : (state.database catalog).table position = some table)
    (passed : (LiteralData.constraints (catalog.uniqueKeys position table.shape)
        { table with rows := change (state.rows.getD position []) } &&
      LiteralData.rowidsDistinct { table with rows := change (state.rows.getD position []) }) = true)
    (fresh : ∀ row ∈ change (state.rows.getD position []),
      row ∈ state.rows.getD position [] ∨ LiteralData.rowAdmitted table.shape row = true) :
    (state.changeRows position change).Holds invariant catalog :=
  laws.write (state.database catalog) position table _ holds found passed
    fun row member => (fresh row member).imp_left fun held => by rwa [KeyState.table_rows found]

/-- For every catalog, state, position and table: if the database of the state has the table at
the position, the catalog has the table's entry there. Proof sketch: the definition of
{name}`Database.table`. -/
theorem KeyState.table_shape {catalog : Catalog} {state : KeyState} {position : Nat} {table : Table}
    (found : (state.database catalog).table position = some table) : catalog.tableAt position = some table.shape := by
  obtain ⟨_, atShape, same⟩ := Option.map_eq_some_iff.mp found
  rw [← same]
  exact atShape

/-- For every invariant with {name}`WriteLaws`, catalog, state, position and change of rows that gives a
sublist of each list of rows: if the state satisfies {name}`KeyState.Holds`, the state after
{name}`KeyState.changeRows` satisfies it. A DELETE of a row makes such a change. Proof sketch: the database
of the changed state is the database after {name}`Database.setRows`, which is the sublist law of
{name}`WriteLaws`. -/
theorem KeyState.holds_changeRows_sublist {invariant : Database → Prop} (laws : WriteLaws invariant)
    {catalog : Catalog} {state : KeyState} (holds : state.Holds invariant catalog) {position : Nat}
    {change : List Row → List Row} (sublist : ∀ rows, (change rows).Sublist rows) :
    (state.changeRows position change).Holds invariant catalog :=
  laws.sublist (state.database catalog) position change holds sublist

/-- For every property of databases and database: if the database has the property, the state
{lit}`{ rows := database.rows }` (the rows of the database, and the default value of each other
field) satisfies {name}`KeyState.Holds` over the catalog of the database. The row engine starts
from this state. Proof sketch: the database of the state is the database. -/
theorem KeyState.holds_start {invariant : Database → Prop} {database : Database}
    (holds : invariant database) : ({ rows := database.rows } : KeyState).Holds invariant database.catalog := holds

end Belay.Sqlite.Model
