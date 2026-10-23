import Belay.Sqlite.Model.Resolution.ResolveState
import Belay.Sqlite.Model.Resolution.PragmaRows
import Belay.Sqlite.Model.Resolution.ForeignKeyPlan

set_option doc.verso true

/-! Resolution of the {lit}`PRAGMA` statements (ADR 0018, D4; ADR 0019, D2). A setting with a
value changes the setting of the state. Every other pragma is a query over the rows of the
pragma ({name}`Belay.Sqlite.Model.Resolved.Source.pragma`), with the columns of SQLite's
pragma, and leaves the state as it is. -/

namespace Belay.Sqlite.Model

/-- The query of the rows of a pragma with the names of its columns: each result column is
the cell at its position, and the query has no condition, order or window. -/
def pragmaQuery (rows : Resolved.PragmaRows) (names : List String) : Resolved.Query :=
  { sources := [{ kind := .inner, source := .pragma rows, condition := none }], filter := none,
    aggregate := false, groupBy := [], columns := (List.range names.length).map fun position => .scalar (.column position),
    names, orderBy := [], offset := 0, limit := none }

/-- The query of a setting: one row with the column of its name ({name}`Syntax.PragmaSetting.sqlName`),
1 when the setting is on and 0 when it is off. -/
def settingQuery (setting : Syntax.PragmaSetting) (on : Bool) : Resolved.Statement :=
  .query (pragmaQuery (.fixed 1 [[.integer (if on then 1 else 0)]]) [setting.sqlName]) []

/-- The query of a check pragma with the limit, for the table at the catalog position or for
every table: one column with the name of the pragma ({name}`Syntax.checkName`). -/
def checkQuery (quick : Bool) (limit : Nat) (table : Option Nat) : Resolved.Statement :=
  .query (pragmaQuery (.check quick limit table) [Syntax.checkName quick]) []

/-- The query of {lit}`PRAGMA foreign_key_check` for the table at the catalog position or for
every table, with the columns of {name}`foreignKeyCheckNames`. -/
def keyCheckQuery (table : Option Nat) : Resolved.Statement :=
  .query (pragmaQuery (.foreignKeyCheck table) foreignKeyCheckNames) []

/-- The prepare error {lit}`foreign key mismatch` of the table at the catalog position, as
{lit}`PRAGMA foreign_key_check` reports it: the error of the first foreign key in the order of
its {lit}`fkid` ({name}`childLinks`) whose parent table has no parent key
({name}`ParentLink.mismatch`, {name}`linkError`). A missing parent table is no error. -/
def Catalog.keyMismatch (catalog : Catalog) (position : Nat) : Option PrepareError :=
  (childLinks catalog.foreignKeyLinks position).findSome? fun link => match link.parent with
    | .mismatch _ => linkError catalog link
    | .located .. | .missing => none

/-- Resolve a pragma against the state:

* {lit}`PRAGMA foreign_keys = value` sets the setting outside a transaction and changes nothing
  inside one, as SQLite does ({name}`Resolved.Statement.setting`);
* {lit}`PRAGMA recursive_triggers = value` sets the setting also inside a transaction;
* the query of a setting is {name}`settingQuery` of its value in the state;
* {lit}`PRAGMA table_info(t)` is the query of {name}`Catalog.tableInfoRows`, and a name of SQLite's
  own tables that the catalog does not have is the restriction
  {name}`RestrictionKind.systemTable`;
* {lit}`PRAGMA foreign_key_list(t)` is the query of {name}`Catalog.foreignKeyListRows`;
* a check pragma is {name}`checkQuery` for every table, or for the named table; a name that
  the catalog does not have is SQLite's prepare error {lit}`no such table`, and a name of
  SQLite's own tables is the restriction {name}`RestrictionKind.systemTable`;
* {lit}`PRAGMA foreign_key_check` is {name}`keyCheckQuery`, for every table or for the named
  table, which is found as for a check pragma. A {lit}`foreign key mismatch`
  ({name}`Catalog.keyMismatch`) fails at prepare, before SQLite reads a row. Without a table
  name, SQLite reports the mismatch of the first table in the order of its schema hash table,
  so the mismatches of two or more tables are the restriction
  {name}`RestrictionKind.foreignKeyMismatchOrder`.

Every form except a setting with a value keeps the state. -/
def resolvePragma (state : ResolveState) : Syntax.Pragma → Except NodeRestriction (Resolved.Statement × ResolveState)
  | .setting .foreignKeys (some on) =>
    let foreignKeys := if state.saved.isSome then state.foreignKeys else on
    .ok (.setting .foreignKeys foreignKeys, { state with foreignKeys })
  | .setting .recursiveTriggers (some on) => .ok (.setting .recursiveTriggers on, { state with recursiveTriggers := on })
  | .setting setting none => .ok (settingQuery setting (state.setting setting), state)
  | .tableInfo table => match state.catalog.tableInfoRows table with
    | some rows => .ok (.query (pragmaQuery (.fixed tableInfoNames.length rows) tableInfoNames) [], state)
    | none => .error { path := [], kind := .systemTable }
  | .foreignKeyList table =>
    .ok (.query (pragmaQuery (.fixed foreignKeyListNames.length (state.catalog.foreignKeyListRows table))
      foreignKeyListNames) [], state)
  | .check quick limit none => .ok (checkQuery quick limit none, state)
  | .check quick limit (some table) => match state.catalog.findTable table with
    | some (position, _) => .ok (checkQuery quick limit (some position), state)
    | none => if reservedName table then .error { path := [], kind := .systemTable }
      else .ok (.prepareError (.noSuchTable table), state)
  | .foreignKeyCheck none => match (List.range state.catalog.length).filterMap state.catalog.keyMismatch with
    | [] => .ok (keyCheckQuery none, state)
    | [error] => .ok (.prepareError error, state)
    | _ :: _ :: _ => .error { path := [], kind := .foreignKeyMismatchOrder }
  | .foreignKeyCheck (some table) => match state.catalog.findTable table with
    | some (position, _) => match state.catalog.keyMismatch position with
      | some error => .ok (.prepareError error, state)
      | none => .ok (keyCheckQuery (some position), state)
    | none => if reservedName table then .error { path := [], kind := .systemTable }
      else .ok (.prepareError (.noSuchTable table), state)

/-- For every state and pragma that resolves, one of these holds:

* the result is a setting with a value, and the next state is the state with the setting at
  that value ({name}`ResolveState.set`);
* the next state is the state, the resolved statement leaves the catalog as it is
  ({name}`Resolved.Statement.applyCatalog`), and it is not control
  ({name}`Resolved.Statement.isControl`).

Proof sketch: by cases on the pragma; each branch is a definition. -/
theorem resolvePragma_cases {state next : ResolveState} {pragma : Syntax.Pragma} {resolved : Resolved.Statement}
    (ok : resolvePragma state pragma = .ok (resolved, next)) :
    (∃ setting on, resolved = .setting setting on ∧ next = state.set on setting) ∨
      (next = state ∧ resolved.applyCatalog state.catalog = state.catalog ∧ resolved.isControl = false) := by
  unfold resolvePragma at ok
  repeat' split at ok
  all_goals first
    | (cases ok; exact .inl ⟨_, _, rfl, rfl⟩)
    | (cases ok; exact .inr ⟨rfl, rfl, rfl⟩)
    | cases ok

end Belay.Sqlite.Model
