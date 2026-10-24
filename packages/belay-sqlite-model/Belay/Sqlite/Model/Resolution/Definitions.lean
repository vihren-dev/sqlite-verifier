import Belay.Sqlite.Model.Resolution.Context
import Belay.Sqlite.Model.Resolution.KeyMerge
import Belay.Sqlite.Model.Resolution.ReadDefaults
import Belay.Sqlite.Model.Resolution.IndexTerms
import Belay.Sqlite.Model.Resolution.GeneratedColumns
import Belay.Sqlite.Model.Resolution.TableOptions
import Belay.Sqlite.Model.Resolution.ParentKeys

set_option doc.verso true

/-! Name resolution of CREATE TABLE and CREATE INDEX ({lit}`AddColumn.lean` resolves ALTER
TABLE ADD COLUMN). The prepare checks follow the order of SQLite 3.51.0's
{lit}`sqlite3StartTable`, {lit}`sqlite3AddColumn`, {lit}`sqlite3AddPrimaryKey`,
{lit}`sqlite3EndTable` and {lit}`sqlite3CreateIndex`, because SQLite reports the first error it finds.
Model restrictions follow the prepare checks: a statement that SQLite refuses needs no model. -/

namespace Belay.Sqlite.Model

/-- The positions of key columns, or {lit}`no such column: %s` for the first name
that no column has. -/
def keyPositions (columns : List CatalogColumn) : List Identifier → Except ExprError (List Nat)
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
def applyConstraint (tableName : Identifier) (definition : Syntax.ColumnDefinition)
    (table : CatalogTable) : Syntax.ColumnConstraint → Except ExprError CatalogTable
  | .primaryKey descending algorithm =>
    if !table.primaryKey.isEmpty then .error (.multiplePrimaryKeys tableName) else
    if (table.columns.getLast?.bind (·.generated)).isSome then .error .generatedInPrimaryKey else
    let position := table.columns.length - 1
    let alias := if aliasesRowid (reportedType definition.declaredType) && !descending then some position else none
    setPrimaryKey table [position] alias descending algorithm
  | .default value sourceText =>
    if !constantDefault value then .error (.defaultNotConstant definition.name) else
    if (table.columns.getLast?.bind (·.generated)).isSome then .error .defaultOnGenerated else
    -- A default that the model does not describe leaves no default here; resolution then
    -- refuses the statement with {lit}`unmodeledDefault` ({lit}`modeledDefault`).
    .ok { table with columns := updateLast table.columns fun column =>
      { column with defaultValue := resolveColumnDefault column.affinity ⟨value, sourceText⟩ } }
  | .notNull algorithm => .ok { table with columns := updateLast table.columns fun column =>
      { column with notNull := true, notNullAlgorithm := algorithm.getD .abort } }
  | .unique algorithm => addUniqueKey table [table.columns.length - 1] algorithm
  | .collate name => match Collation.named? name with
    | none => .error (.noSuchCollation name)
    | some collation => .ok { table with columns := updateLast table.columns fun column => { column with collation } }
  | .check .. => .ok table
  | .generated _ kind =>
    if (table.columns.getLast?.bind (·.generated)).isSome then .error (.errorInGenerated definition.name) else
    let stored := kind.any (·.isKeyword (bytes! "stored"))
    if kind.any (fun word => !word.isKeyword (bytes! "stored") && !word.isKeyword (bytes! "virtual")) then
      .error (.errorInGenerated definition.name) else
    if table.primaryKey.contains (table.columns.length - 1) then .error .generatedInPrimaryKey else
    if definition.constraints.any (· matches .default ..) &&
        (table.columns.getLast?.bind (·.defaultValue)).isSome then .error (.errorInGenerated definition.name) else
    -- The expression resolves over the whole table in {lit}`resolveGeneratedColumns`.
    .ok { table with columns := updateLast table.columns fun column =>
      { column with generated := some { expression := .literal .null, stored } } }
  | .references referenced columns onDelete onUpdate =>
    if columns.length > 1 then .error (.foreignKeyOneColumn definition.name referenced) else
    let key : ForeignKey := { table := referenced, columns := [table.columns.length - 1], referenced := columns,
                              onDelete, onUpdate }
    .ok { table with columns := updateLast table.columns fun column =>
      { column with foreignKeys := column.foreignKeys ++ [key] } }
  | .deferral deferred => .ok (table.deferLast deferred)

/-- Add the column definitions in written order: {lit}`too many columns on %s` when
a column would exceed the limit, then {lit}`duplicate column name: %s`, then each
column constraint ({lit}`sqlite3AddColumn` and the constraint actions). Each column has the
strict type of the table's {name}`CatalogTable.strict` ({name}`definedColumn`). -/
def addDefinitions (limit : Nat) (tableName : Identifier) (table : CatalogTable) :
    List Syntax.ColumnDefinition → Except ExprError CatalogTable
  | [] => .ok table
  | definition :: rest => do
    if table.columns.length + 1 > limit then throw (.tooManyColumns tableName)
    if (columnPosition table.columns definition.name).isSome then
      throw (.duplicateColumn definition.name)
    let added := { table with columns := table.columns ++ [definedColumn table.strict definition] }
    let constrained ← definition.constraints.foldlM (applyConstraint tableName definition) added
    addDefinitions limit tableName constrained rest

/-- Apply the table constraints in written order. A table PRIMARY KEY with one
column of declared type INTEGER is a rowid alias, whatever its sort order. A CHECK waits
for {name}`resolveTableChecks`. A {lit}`FOREIGN KEY` adds a {name}`ForeignKey` after SQLite's
checks: the number of referenced columns, then each column; its deferral clause sets whether it
is deferred ({name}`CatalogTable.deferLast`). -/
def addTableConstraints (tableName : Identifier) (table : CatalogTable) :
    List Syntax.TableConstraint → Except ExprError CatalogTable
  | [] => .ok table
  | .primaryKey [] _ :: _ | .unique [] _ :: _ => throw .emptyKeyList
  | .primaryKey names algorithm :: rest => do
    if !table.primaryKey.isEmpty then throw (.multiplePrimaryKeys tableName)
    let positions ← keyPositions table.columns names
    if positions.any fun position => (table.columns[position]?.bind (·.generated)).isSome then
      throw .generatedInPrimaryKey
    let alias := match positions with
      | [position] => if aliasesRowid (table.columns[position]?.bind (·.declaredType)) then some position else none
      | _ => none
    let keyed ← setPrimaryKey table positions alias table.primaryKeyDescending algorithm
    addTableConstraints tableName keyed rest
  | .unique names algorithm :: rest => do
    let positions ← keyPositions table.columns names
    let keyed ← addUniqueKey table positions algorithm
    addTableConstraints tableName keyed rest
  | .check .. :: rest => addTableConstraints tableName table rest
  | .foreignKey columns target referenced onDelete onUpdate :: rest => do
    if !referenced.isEmpty && referenced.length != columns.length then throw .foreignKeyColumnCount
    let positions ← columns.mapM fun name => match columnPosition table.columns name with
      | some position => .ok position
      | none => .error (.unknownForeignKeyColumn name)
    let key : ForeignKey := { table := target, columns := positions, referenced, onDelete, onUpdate }
    addTableConstraints tableName { table with foreignKeys := table.foreignKeys ++ [key] } rest
  | .deferral deferred :: rest => addTableConstraints tableName (table.deferLast deferred) rest

/-- The exact statistics tables that ANALYZE creates, which a catalog description may contain. -/
def statisticsTable (name : Identifier) (columns : List Syntax.ColumnDefinition)
    (constraints : List Syntax.TableConstraint) : Bool :=
  let plain := fun (names : List Identifier) => columns == names.map fun column =>
    { name := column, declaredType := none, constraints := [] }
  constraints.isEmpty && (statisticsColumns name.folded).any plain

/-- Resolve CREATE TABLE, of a catalog description or in a script. Path 1 is the column list
and path 2 the table constraints. A {lit}`WITHOUT ROWID` table
({name}`CatalogTable.asWithoutRowid`) without a primary key is SQLite's
{lit}`PRIMARY KEY missing on table %s`, after the errors of its definitions and of a
{lit}`STRICT` table's types ({name}`strictTypeError`), whose key columns are NOT NULL
({name}`CatalogTable.withStrictKeys`); then the CHECK
constraints resolve ({name}`resolveTableChecks`) under the profile's {lit}`DQS_DDL`. -/
def resolveCreateTable (context : ResolveContext) (catalog : Catalog)
    (name : Identifier) (columns : List Syntax.ColumnDefinition)
    (constraints : List Syntax.TableConstraint) (options : Syntax.TableOptions := {}) : StatementResolution :=
  let statistics := context.mode == .description && statisticsTable name columns constraints
  if reservedName name && !statistics then
    if context.mode == .description then restrict [0] .engineTable
    else prepareError catalog (.expression (.reservedName name))
  else match catalog.find name with
  | some (_, { entry := .table _, .. }) => prepareError catalog (.tableExists name)
  | some (_, { entry := .index _, .. }) => prepareError catalog (.indexNameUsed name)
  | some (_, { entry := .trigger _, .. }) | none =>
    match addDefinitions context.profile.limits.columns name { columns := [], strict := options.strict } columns >>=
        (addTableConstraints name · constraints) with
    | .error error => prepareError catalog (.expression error)
    | .ok table =>
      match strictTypeError name table with
      | some error => prepareError catalog (.expression error)
      | none =>
      let table := if options.withoutRowid then table.asWithoutRowid else table.withStrictKeys
      if options.withoutRowid && table.primaryKey.isEmpty then
        prepareError catalog (.expression (.primaryKeyMissing name))
      else if table.columns.all (·.generated.isSome) then prepareError catalog (.expression .onlyGeneratedColumns)
      else match resolveTableChecks context.profile.dqsDdl (Scope.single name table.columns !table.withoutRowid)
          table columns constraints with
      | .error issue => issueResolution catalog [] issue
      | .ok table =>
      match resolveGeneratedColumns context.profile.dqsDdl (Scope.single name table.columns false) table columns with
      | .error issue => issueResolution catalog [] issue
      | .ok table =>
        if columns.any (rowidName ·.name) then restrict [1] .rowidColumnName
        else if columns.any (!·.constraints.all Syntax.ColumnConstraint.modeledDefault) then
          restrict [1] .unmodeledDefault
        else .ok (.createTable catalog.length name table, catalog.createTable name table)

/-- Resolve CREATE INDEX, of a catalog description or in a script, in SQLite's order: the
table, its reserved name, the index name, the name in use, the key terms
({name}`indexKeys`, path 3) and the filter ({name}`indexFilter`, path 4), both over the
table alone and under the profile's {lit}`DQS_DDL`. A CREATE INDEX that runs builds the
index over the existing rows in execution. -/
def resolveCreateIndex (context : ResolveContext) (catalog : Catalog)
    (name : Identifier) (unique : Bool) (tableName : Identifier) (terms : List Syntax.OrderTerm)
    (filter : Option Syntax.Expr) : StatementResolution :=
  match catalog.findTable tableName with
  | none => prepareError catalog (.noSuchTable tableName)
  | some (position, table) =>
    if reservedName tableName then prepareError catalog (.expression (.tableMayNotBeIndexed tableName))
    else if reservedName name then prepareError catalog (.expression (.reservedName name))
    else match catalog.find name with
    | some (_, { entry := .table _, .. }) => prepareError catalog (.tableNameUsed name)
    | some (_, { entry := .index _, .. }) => prepareError catalog (.indexExists name)
    | some (_, { entry := .trigger _, .. }) | none =>
      let scope := Scope.single tableName table.columns !table.withoutRowid
      let dqs := context.profile.dqsDdl
      match indexKeys dqs scope table.columns terms with
      | .error issue => issueResolution catalog [3] issue
      | .ok keys => match indexFilter dqs scope filter with
        | .error issue => issueResolution catalog [4] issue
        | .ok resolvedFilter =>
          let created := { table := position, keys, unique, filter := resolvedFilter }
          .ok (.createIndex catalog.length name created, catalog.createIndex name created)

end Belay.Sqlite.Model
