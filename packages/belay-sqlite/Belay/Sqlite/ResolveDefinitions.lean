import Belay.Sqlite.ResolveValues

set_option doc.verso true

/-! Name resolution of CREATE TABLE, CREATE INDEX and ALTER TABLE ADD COLUMN. The
prepare checks follow the order of SQLite 3.51.0's {lit}`sqlite3StartTable`,
{lit}`sqlite3AddColumn`, {lit}`sqlite3AddPrimaryKey`, {lit}`sqlite3CreateIndex` and
{lit}`sqlite3AlterFinishAddColumn`, because SQLite reports the first error it finds.
Model restrictions follow the prepare checks: a statement that SQLite refuses needs
no model. -/

namespace Belay.Sqlite

/-- Whether statements describe the starting schema or run as a migration. A
schema description may contain the engine's statistics tables, constraints and
indexes. A migration CREATE TABLE has plain columns, and a migration has no
CREATE INDEX, as the execution semantics require. -/
inductive Mode where
  /-- The statements describe the starting schema. -/
  | schema
  /-- The statements run as a migration. -/
  | migration
  deriving Repr, DecidableEq

/-- The inputs of resolution besides the catalog. -/
structure ResolveContext where
  /-- The execution profile, which supplies the limits. -/
  profile : Profile
  /-- Whether the statements describe the schema or run as a migration. -/
  mode : Mode

/-- The resolution of one statement: the resolved statement and the catalog after
it succeeds, or a model restriction. -/
abbrev StatementResolution := Except Restriction (Resolved.Statement × Catalog)

/-- Whether the folded name starts with {lit}`sqlite_`, which SQLite reserves. -/
def reservedName (name : String) : Bool := (normalizeIdentifier name).startsWith "sqlite_"

/-- Whether a column name is one of SQLite's rowid names, which the model keeps
for the physical rowid. -/
def rowidName (name : String) : Bool :=
  ["rowid", "_rowid_", "oid"].contains (normalizeIdentifier name)

/-- Whether a DEFAULT expression is constant for SQLite: a literal, a signed
literal, a time keyword, or an identifier, which SQLite stores as text. -/
def constantDefault : Syntax.Expr → Bool
  | .null | .numeric _ | .string _ | .blob _ | .currentTime _ | .identifier .. => true
  | .negate operand | .positive operand => constantDefault operand
  | .equals .. => false

/-- The positions of key columns, or {lit}`no such column: %s` for the first name
that no column has. -/
def keyPositions (columns : List CatalogColumn) : List String → Except PrepareError (List Nat)
  | [] => .ok []
  | name :: rest => match columnPosition columns name with
    | some position => (keyPositions columns rest).map (position :: ·)
    | none => .error (.noSuchColumn name)

/-- Apply the function to the last element of a list; an empty list stays empty. -/
def updateLast (items : List α) (change : α → α) : List α :=
  match items with
  | [] => []
  | [last] => [change last]
  | first :: rest => first :: updateLast rest change

/-- Apply one column constraint of the last column of a table being created. -/
def applyConstraint (tableName : String) (definition : Syntax.ColumnDefinition)
    (table : CatalogTable) : Syntax.ColumnConstraint → Except PrepareError CatalogTable
  | .primaryKey descending =>
    if !table.primaryKey.isEmpty then .error (.multiplePrimaryKeys tableName) else
    let position := table.columns.length - 1
    let alias := if aliasesRowid definition.declaredType && !descending then some position else none
    .ok { table with primaryKey := [position], rowidAlias := alias }
  | .default value =>
    if !constantDefault value then .error (.defaultNotConstant definition.name) else
    .ok { table with columns := updateLast table.columns fun column => { column with defaultValue := some value } }
  | .notNull => .ok { table with columns := updateLast table.columns fun column => { column with notNull := true } }
  | .unique => .ok { table with uniqueKeys := table.uniqueKeys ++ [[table.columns.length - 1]] }

/-- Add the column definitions in written order: {lit}`too many columns on %s` when
a column would exceed the limit, then {lit}`duplicate column name: %s`, then each
column constraint ({lit}`sqlite3AddColumn` and the constraint actions). -/
def addDefinitions (limit : Nat) (tableName : String) (table : CatalogTable) :
    List Syntax.ColumnDefinition → Except PrepareError CatalogTable
  | [] => .ok table
  | definition :: rest => do
    if table.columns.length + 1 > limit then throw (.tooManyColumns tableName)
    if (columnPosition table.columns definition.name).isSome then
      throw (.duplicateColumn definition.name)
    let column : CatalogColumn := { name := definition.name, declaredType := definition.declaredType }
    let added := { table with columns := table.columns ++ [column] }
    let constrained ← definition.constraints.foldlM (applyConstraint tableName definition) added
    addDefinitions limit tableName constrained rest

/-- Apply the table constraints in written order. A table PRIMARY KEY with one
column of declared type INTEGER is a rowid alias, whatever its sort order. -/
def addTableConstraints (tableName : String) (table : CatalogTable) :
    List Syntax.TableConstraint → Except PrepareError CatalogTable
  | [] => .ok table
  | .primaryKey names :: rest => do
    if !table.primaryKey.isEmpty then throw (.multiplePrimaryKeys tableName)
    let positions ← keyPositions table.columns names
    let alias := match positions with
      | [position] => if aliasesRowid (table.columns[position]?.bind (·.declaredType)) then some position else none
      | _ => none
    addTableConstraints tableName { table with primaryKey := positions, rowidAlias := alias } rest
  | .unique names :: rest => do
    let positions ← keyPositions table.columns names
    addTableConstraints tableName { table with uniqueKeys := table.uniqueKeys ++ [positions] } rest

/-- The exact statistics tables that ANALYZE creates, which a schema may contain. -/
def statisticsTable (name : String) (columns : List Syntax.ColumnDefinition)
    (constraints : List Syntax.TableConstraint) : Bool :=
  let plain := fun (names : List String) => columns == names.map fun column =>
    { name := column, declaredType := none, constraints := [] }
  constraints.isEmpty && match normalizeIdentifier name with
    | "sqlite_stat1" => plain ["tbl", "idx", "stat"]
    | "sqlite_stat4" => plain ["tbl", "idx", "neq", "nlt", "ndlt", "sample"]
    | _ => false

/-- A prepare error leaves the catalog unchanged. -/
def prepareError (catalog : Catalog) (error : PrepareError) : StatementResolution :=
  .ok (.prepareError error, catalog)

/-- A model restriction at a path of statement {lit}`index`. -/
def restrict (index : Nat) (path : List Nat) (reason : String) : StatementResolution :=
  .error { statement := index, path := path, reason := reason }

/-- Resolve CREATE TABLE. Path 1 is the column list and path 2 the table constraints. -/
def resolveCreateTable (context : ResolveContext) (catalog : Catalog) (index : Nat)
    (name : String) (columns : List Syntax.ColumnDefinition)
    (constraints : List Syntax.TableConstraint) : StatementResolution :=
  let statistics := context.mode == .schema && statisticsTable name columns constraints
  if reservedName name && !statistics then
    if context.mode == .schema then restrict index [0] "engine-managed tables other than sqlite_stat1 and sqlite_stat4 are not modeled"
    else prepareError catalog (.reservedName name)
  else match catalog.find name with
  | some (_, { entry := .table _, .. }) => prepareError catalog (.tableExists name)
  | some (_, { entry := .index _, .. }) => prepareError catalog (.indexNameUsed name)
  | none =>
    match addDefinitions context.profile.limits.columns name { columns := [] } columns >>=
        (addTableConstraints name · constraints) with
    | .error error => prepareError catalog error
    | .ok table =>
      if columns.any (rowidName ·.name) then restrict index [1] "column names that hide the rowid are not modeled"
      else if table.rowidAlias.isSome then restrict index [1] "INTEGER PRIMARY KEY rowid aliases are not modeled"
      else if context.mode == .migration && (!constraints.isEmpty || columns.any (!·.constraints.isEmpty)) then
        restrict index [1] "constraints and defaults in a migration CREATE TABLE are not modeled"
      else if columns.any (·.constraints.any fun | .default (.currentTime keyword) => normalizeIdentifier keyword != "current_timestamp" | .default _ => true | _ => false) then
        restrict index [1] "only the CURRENT_TIMESTAMP default is modeled"
      else .ok (.createTable name table, catalog ++ [{ name := name, entry := .table table }])

/-- Resolve CREATE INDEX. A migration has no CREATE INDEX in the model. -/
def resolveCreateIndex (context : ResolveContext) (catalog : Catalog) (index : Nat)
    (name : String) (unique : Bool) (tableName : String) (columns : List String) : StatementResolution :=
  if context.mode == .migration then restrict index [] "CREATE INDEX in a migration is not modeled" else
  match catalog.findTable tableName with
  | none => prepareError catalog (.noSuchTable tableName)
  | some (position, table) =>
    if reservedName tableName then prepareError catalog (.tableMayNotBeIndexed tableName)
    else if reservedName name then prepareError catalog (.reservedName name)
    else match catalog.find name with
    | some (_, { entry := .table _, .. }) => prepareError catalog (.tableNameUsed name)
    | some (_, { entry := .index _, .. }) => prepareError catalog (.indexExists name)
    | none => match keyPositions table.columns columns with
      | .error error => prepareError catalog error
      | .ok positions => .ok (.createIndex name { table := position, columns := positions, unique },
          catalog ++ [{ name := name, entry := .index { table := position, columns := positions, unique } }])

/-- Resolve ALTER TABLE ADD COLUMN. Path 1 is the column definition. -/
def resolveAddColumn (context : ResolveContext) (catalog : Catalog) (index : Nat)
    (tableName : String) (definition : Syntax.ColumnDefinition) : StatementResolution :=
  match catalog.findTable tableName with
  | none => prepareError catalog (.noSuchTable tableName)
  | some (position, table) =>
    if reservedName tableName then prepareError catalog (.tableMayNotBeAltered tableName)
    else if table.columns.length + 1 > context.profile.limits.columns then
      prepareError catalog (.tooManyColumns tableName)
    else if (columnPosition table.columns definition.name).isSome then
      prepareError catalog (.duplicateColumn definition.name)
    else if definition.constraints.any (· matches .primaryKey _) && !table.primaryKey.isEmpty then
      prepareError catalog (.multiplePrimaryKeys tableName)
    else if definition.constraints.any (fun | .default value => !constantDefault value | _ => false) then
      prepareError catalog (.defaultNotConstant definition.name)
    else if definition.constraints.any (· matches .primaryKey _) then prepareError catalog .cannotAddPrimaryKey
    else if definition.constraints.any (· matches .unique) then prepareError catalog .cannotAddUnique
    else if rowidName definition.name then restrict index [1] "column names that hide the rowid are not modeled"
    else if !definition.constraints.isEmpty then
      restrict index [1] "only a nullable column without a default can be added"
    else
      let column : CatalogColumn := { name := definition.name, declaredType := definition.declaredType }
      let object := { name := (catalog[position]?.map (·.name)).getD tableName,
                      entry := .table { table with columns := table.columns ++ [column] } }
      .ok (.addColumn position column, catalog.set position object)

end Belay.Sqlite
