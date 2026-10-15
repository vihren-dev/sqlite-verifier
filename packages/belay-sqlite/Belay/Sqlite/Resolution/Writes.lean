import Belay.Sqlite.Resolution.Definitions
import Belay.Sqlite.Resolution.KeyDomain
import Belay.Sqlite.Resolution.Returning

set_option doc.verso true

/-! Name resolution of INSERT and UPDATE. The checks follow the order of SQLite
3.51.0's {lit}`sqlite3MultiValues`, {lit}`sqlite3Insert` and {lit}`sqlite3Update`.
A resolved INSERT row has one value for each table column in table order: a named
column gets the written value and every other column its default. -/

namespace Belay.Sqlite

/-- Resolve the items in order from a starting position, and stop at the first issue. -/
def resolveAllFrom (resolveOne : Nat → α → Except ValueIssue β) (start : Nat) :
    List α → Except ValueIssue (List β)
  | [] => .ok []
  | item :: rest => do
    let value ← resolveOne start item
    let values ← resolveAllFrom resolveOne (start + 1) rest
    return value :: values

/-- Resolve a list in order from position zero, and stop at the first issue. -/
def resolveAll (resolveOne : Nat → α → Except ValueIssue β) (items : List α) : Except ValueIssue (List β) :=
  resolveAllFrom resolveOne 0 items

/-- Turn a value issue into the statement's resolution: a prepare error keeps the
catalog, a restriction refuses the script. -/
def issueResolution (catalog : Catalog) (index : Nat) (path : List Nat) : ValueIssue → StatementResolution
  | .prepare error => prepareError catalog error
  | .restriction inner reason => restrict index (path ++ inner) reason

/-- The table column positions of an INSERT column list, or
{lit}`table %S has no column named %s` for the first unknown name. -/
def insertPositions (tableName : String) (columns : List CatalogColumn) :
    List String → Except PrepareError (List Nat)
  | [] => .ok []
  | name :: rest => match columnPosition columns name with
    | some position => (insertPositions tableName columns rest).map (position :: ·)
    | none => .error (.tableHasNoColumn tableName name)

/-- One full row in table order: the written value of a named column, or its default,
stored with the column's affinity ({name}`storeValue`). -/
def fullRow (columns : List CatalogColumn) (positions : List Nat) (row : List Value) :
    Except ValueIssue (List Value) :=
  resolveAll (fun position column => do
    let value ← match positions.idxOf? position with
      | some written => .ok (row[written]?.getD .null)
      | none => defaultValue column
    .ok (storeValue column.affinity value)) columns

/-- Resolve INSERT. Path 1 is the column list and path 2 the rows. -/
def resolveInsert (context : ResolveContext) (catalog : Catalog) (index : Nat) (tableName : String)
    (names : Option (List String)) (rows : List (List Syntax.Expr))
    (returning : List Syntax.ResultColumn) : StatementResolution :=
  let width := (rows.head?.map List.length).getD 0
  if rows.any (·.length != width) then prepareError catalog .valuesDiffer else
  match catalog.findTable tableName with
  | none => prepareError catalog (.noSuchTable tableName)
  | some (position, table) =>
    let positions := match names with
      | some written => insertPositions tableName table.columns written
      | none => .ok (List.range table.columns.length)
    match positions with
    | .error error => prepareError catalog error
    | .ok positions =>
      match resolveAll (fun row values => (resolveAll (fun _ => constantValue context.profile.dqsDml)
          values).mapError (·.under [row])) rows with
      | .error issue => issueResolution catalog index [2] issue
      | .ok values =>
        if names.isNone && width != table.columns.length then
          prepareError catalog (.valueCount tableName table.columns.length width)
        else if names.isSome && width != positions.length then
          prepareError catalog (.valuesForColumns width positions.length)
        else if positions.eraseDups.length != positions.length then
          restrict index [1] .insertColumnTwice
        else match resolveAll (fun _ row => fullRow table.columns positions row) values with
          | .error issue => issueResolution catalog index [2] issue
          | .ok full =>
            let keys := catalog.uniqueKeys position table
            match keyDomainRestriction table.columns keys (fun row => [2, row])
                (full.map (·.mapIdx fun position value => (position, value))) with
            | some (path, reason) => restrict index path reason
            | none => match resolveReturning context.profile.dqsDml (Scope.single tableName table.columns) returning with
              | .error issue => issueResolution catalog index [3] issue
              | .ok columns => .ok (.insert position full keys columns, catalog)

end Belay.Sqlite
