import Belay.Sqlite.Resolution.Definitions
import Belay.Sqlite.Resolution.Upserts

set_option doc.verso true

/-! Name resolution of INSERT and UPDATE. The checks follow the order of SQLite
3.51.0's {lit}`sqlite3MultiValues`, {lit}`sqlite3Insert` and {lit}`sqlite3Update`.
A resolved INSERT row has one value for each table column in table order: a named
column gets the written value and every other column its default. -/

namespace Belay.Sqlite

/-- The value of a column's DEFAULT when INSERT omits the column: NULL without a
default. The only default that a catalog holds is {lit}`CURRENT_TIMESTAMP`
(resolution refuses the others with {name}`RestrictionKind.unmodeledDefault`), and
its time value is a model restriction. -/
def defaultValue (column : CatalogColumn) : Except ValueIssue Value :=
  match column.defaultValue with
  | none => .ok .null
  | some (.currentTime _) => .error (.restriction [] .timeValue)
  | some .null | some (.numeric _) | some (.string _) | some (.blob _) | some (.identifier ..)
  | some (.negate _) | some (.positive _) | some (.equals ..) | some (.compare ..) | some (.and ..)
  | some (.or ..) | some (.not _) | some (.isNull ..) | some (.callStar _) | some (.call ..)
  | some (.arithmetic ..) | some (.cast ..) | some (.callPair ..) | some (.more ..) | some (.qualified ..) =>
    .error (.restriction [] .unmodeledDefault)

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

/-- The {lit}`ON CONFLICT` algorithm of each key of {name}`Catalog.uniqueKeys`, in its
order: the primary key's, each UNIQUE constraint's, and ABORT for each unique index. -/
def Catalog.keyAlgorithms (catalog : Catalog) (position : Nat) (table : CatalogTable) : List ConflictAlgorithm :=
  (if table.primaryKey.isEmpty then [] else [table.primaryKeyAlgorithm.getD .abort]) ++
    (table.keyedUniqueAlgorithms.map (·.getD .abort)) ++
    catalog.filterMap fun object => match object.entry with
      | .index index => if index.table == position && index.unique then some .abort else none
      | .table _ => none

/-- The algorithm of each constraint of an INSERT into the table: the statement's
{lit}`OR` algorithm when it has one (R-33948-22286), else the algorithm of the
constraint ({lit}`constraints` for the keys, {name}`CatalogColumn.notNullAlgorithm` for
NOT NULL). -/
def insertPolicy (table : CatalogTable) (constraints : List ConflictAlgorithm) (algorithm : Option ConflictAlgorithm) :
    Resolved.ConflictPolicy :=
  { keys := constraints.map fun own => algorithm.getD own,
    notNull := table.columns.map fun column => algorithm.getD column.notNullAlgorithm }

/-- Whether the policy gives two keys different algorithms other than REPLACE, whose order
SQLite decides internally ({name}`RestrictionKind.mixedConflictAlgorithms`). -/
def Resolved.ConflictPolicy.mixed (policy : Resolved.ConflictPolicy) : Bool :=
  (policy.keys.filter (· != .replace)).eraseDups.length > 1

/-- Whether a NOT NULL column with a default has REPLACE, which would store the default
({name}`RestrictionKind.replaceDefault`). -/
def replacesDefault (table : CatalogTable) (policy : Resolved.ConflictPolicy) : Bool :=
  (table.columns.zip policy.notNull).any fun (column, algorithm) =>
    column.notNull && column.defaultValue.isSome && algorithm == .replace

/-- Whether every algorithm of the policy is ABORT, the behavior of a plain INSERT. -/
def Resolved.ConflictPolicy.aborts (policy : Resolved.ConflictPolicy) : Bool :=
  policy.keys.all (· == .abort) && policy.notNull.all (· == .abort)

/-- Resolve INSERT. Path 1 is the column list, path 2 the rows, path 3 the
{lit}`ON CONFLICT` clauses ({name}`resolveConflict`) and path 4 the {lit}`RETURNING`
columns. An INSERT without clauses whose algorithms are all ABORT
({name}`insertPolicy`) is {name}`Resolved.Statement.insert`; any other INSERT is
{name}`Resolved.Statement.upsert`. -/
def resolveInsert (context : ResolveContext) (catalog : Catalog) (index : Nat) (tableName : String)
    (names : Option (List String)) (rows : List (List Syntax.Expr)) (conflicts : List Syntax.ConflictClause)
    (algorithm : Option ConflictAlgorithm) (returning : List Syntax.ResultColumn) : StatementResolution :=
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
            match resolveAll (resolveConflict context.profile.dqsDml tableName table keys) conflicts with
            | .error issue => issueResolution catalog index [3] issue
            | .ok clauses =>
              match resolveReturning context.profile.dqsDml (Scope.single tableName table.columns) returning with
              | .error issue => issueResolution catalog index [4] issue
              | .ok columns =>
                let policy := insertPolicy table (catalog.keyAlgorithms position table) algorithm
                if policy.mixed then restrict index [] .mixedConflictAlgorithms
                else if replacesDefault table policy then restrict index [] .replaceDefault
                else if clauses.isEmpty && policy.aborts then .ok (.insert position full keys columns, catalog)
                else .ok (.upsert position full clauses keys columns policy, catalog)

end Belay.Sqlite
