import Belay.Sqlite.ResolveDefinitions

set_option doc.verso true

/-! Name resolution of INSERT and UPDATE. The checks follow the order of SQLite
3.51.0's {lit}`sqlite3MultiValues`, {lit}`sqlite3Insert` and {lit}`sqlite3Update`.
A resolved INSERT row has one value for each table column in table order: a named
column gets the written value and every other column its default. -/

namespace Belay.Sqlite

/-- Prefix the paths of model restrictions with the node's position. -/
def ValueIssue.under (prefix_ : List Nat) : ValueIssue → ValueIssue
  | .restriction path reason => .restriction (prefix_ ++ path) reason
  | .prepare error => .prepare error

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

/-- The value of a column's DEFAULT when INSERT omits the column: NULL without a
default, else the default literal. A time default is a model restriction. -/
def defaultValue (dqs : Bool) (column : CatalogColumn) : Except ValueIssue Value :=
  match column.defaultValue with
  | none => .ok .null
  | some (.identifier name _) => .ok (.text name.toUTF8.toList)
  | some value => literalValue dqs value

/-- The value of a SET expression with the table's columns in scope. A name of a
column is a column reference, which the first scope does not model; any other
expression is a literal as in {name}`literalValue`. -/
def assignedValue (columns : List CatalogColumn) (dqs : Bool) : Syntax.Expr → Except ValueIssue Value
  | .identifier name doubleQuoted =>
    if (columnPosition columns name).isSome then
      .error (.restriction [] "column references in values are not modeled; write a literal value")
    else literalValue dqs (.identifier name doubleQuoted)
  | .null => literalValue dqs .null
  | .numeric text => literalValue dqs (.numeric text)
  | .string bytes => literalValue dqs (.string bytes)
  | .blob bytes => literalValue dqs (.blob bytes)
  | .currentTime keyword => literalValue dqs (.currentTime keyword)
  | .negate operand => literalValue dqs (.negate operand)
  | .positive operand => literalValue dqs (.positive operand)
  | .equals left right => literalValue dqs (.equals left right)

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

/-- One full row in table order: the written value of a named column, or its default.
Each value must be stored unchanged by the column's affinity. -/
def fullRow (dqs : Bool) (columns : List CatalogColumn) (positions : List Nat) (row : List Value) :
    Except ValueIssue (List Value) :=
  resolveAll (fun position column => do
    let value ← match positions.idxOf? position with
      | some written => .ok (row[written]?.getD .null)
      | none => defaultValue dqs column
    storedValue column.affinity value [position]) columns

/-- Resolve INSERT. Path 1 is the column list and path 2 the rows. -/
def resolveInsert (context : ResolveContext) (catalog : Catalog) (index : Nat) (tableName : String)
    (names : Option (List String)) (rows : List (List Syntax.Expr)) : StatementResolution :=
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
      match resolveAll (fun row values => (resolveAll (fun _ => literalValue context.profile.dqsDml)
          values).mapError (·.under [row])) rows with
      | .error issue => issueResolution catalog index [2] issue
      | .ok values =>
        if names.isNone && width != table.columns.length then
          prepareError catalog (.valueCount tableName table.columns.length width)
        else if names.isSome && width != positions.length then
          prepareError catalog (.valuesForColumns width positions.length)
        else if positions.eraseDups.length != positions.length then
          restrict index [1] "a column named twice in INSERT is not modeled; name each column once"
        else match resolveAll (fun _ row => fullRow context.profile.dqsDml table.columns positions row) values with
          | .error issue => issueResolution catalog index [2] issue
          | .ok full => .ok (.insert position full, catalog)

/-- Whether the model compares a stored value with an integer literal without a
conversion: the column has INTEGER, NUMERIC or BLOB affinity, and the execution
semantics requires its stored values to be integers or NULL. -/
def integerComparable : Affinity → Bool
  | .integer | .numeric | .blob => true
  | .text | .real => false

/-- Resolve the optional WHERE of UPDATE: none, or one column compared with an
integer. Other filters, and a comparison that would convert values, are model
restrictions. Path 2 is the filter. -/
def resolveFilter (context : ResolveContext) (columns : List CatalogColumn) :
    Option Syntax.Expr → Except ValueIssue (Option (Nat × Value))
  | none => .ok none
  | some (.equals (.identifier name doubleQuoted) right) =>
    match columnPosition columns name with
    | none =>
      if doubleQuoted && context.profile.dqsDml then .error (.restriction [0] "a comparison of two literals is not modeled; compare a column with a literal")
      else .error (.prepare (.noSuchColumn name))
    | some position => do
      let value ← (assignedValue columns context.profile.dqsDml right).mapError (·.under [1])
      let affinity := (columns[position]?.map CatalogColumn.affinity).getD .blob
      match value with
      | .integer _ =>
        if integerComparable affinity then .ok (some (position, value))
        else .error (.restriction [1] "only an integer equality with an INTEGER, NUMERIC or BLOB column is modeled; compare such a column with an integer literal")
      | .null | .real _ | .text _ | .blob _ =>
        .error (.restriction [1] "only an integer equality with an INTEGER, NUMERIC or BLOB column is modeled; compare such a column with an integer literal")
  | some (.equals (.null) _) | some (.equals (.numeric _) _) | some (.equals (.string _) _)
  | some (.equals (.blob _) _) | some (.equals (.currentTime _) _) | some (.equals (.negate _) _)
  | some (.equals (.positive _) _) | some (.equals (.equals ..) _) | some .null | some (.numeric _)
  | some (.string _) | some (.blob _) | some (.currentTime _) | some (.identifier ..)
  | some (.negate _) | some (.positive _) =>
    .error (.restriction [] "only a column equality filter is modeled; write WHERE column = integer")

/-- Resolve UPDATE. Path 1 is the assignment list and path 2 the filter. -/
def resolveUpdate (context : ResolveContext) (catalog : Catalog) (index : Nat) (tableName : String)
    (assignments : List (String × Syntax.Expr)) (filter : Option Syntax.Expr) : StatementResolution :=
  match catalog.findTable tableName with
  | none => prepareError catalog (.noSuchTable tableName)
  | some (position, table) =>
    match resolveAll (fun item (_, value) => (assignedValue table.columns context.profile.dqsDml value).mapError
        (·.under [item, 1])) assignments with
    | .error issue => issueResolution catalog index [1] issue
    | .ok values =>
      match assignments.mapM (fun (name, _) => (columnPosition table.columns name).elim
          (Except.error (PrepareError.noSuchColumn name)) Except.ok) with
      | .error error => prepareError catalog error
      | .ok positions =>
        match resolveFilter context table.columns filter with
        | .error issue => issueResolution catalog index [2] issue
        | .ok resolvedFilter =>
          if positions.eraseDups.length != positions.length then
            restrict index [1] "a column assigned twice in UPDATE is not modeled; assign each column once"
          else match resolveAll (fun item (column, value) =>
              storedValue ((table.columns[column]?.map CatalogColumn.affinity).getD .blob) value [item, 1])
              (positions.zip values) with
            | .error issue => issueResolution catalog index [1] issue
            | .ok stored => .ok (.update position (positions.zip stored) resolvedFilter, catalog)

end Belay.Sqlite
