import Belay.Sqlite.Model.Resolution.Catalog
import Belay.Sqlite.Model.Resolution.PrepareErrors
import Belay.Sqlite.Model.Resolution.SyntaxDefinitions

set_option doc.verso true

/-! The catalog rules of the table options (ADR 0014, D4 and D6) that SQLite 3.51.0 applies
in {lit}`sqlite3AddColumn` and {lit}`sqlite3EndTable`: a {lit}`WITHOUT ROWID` table's key,
and a {lit}`STRICT` table's column types, the errors of its types, and the NOT NULL of its
primary-key columns. -/

namespace Belay.Sqlite.Model

/-- A table as {lit}`WITHOUT ROWID` makes it (ADR 0014, D4; {lit}`convertToWithoutRowidTable`):
no rowid alias, each primary-key column NOT NULL, with ABORT unless it declares its own
NOT NULL, and a key without the repeated occurrences of a column, which SQLite ignores
(R-03887-49864). The index of a key that was a rowid alias comes after the UNIQUE keys
({name}`CatalogTable.uniqueBeforePrimary`), because SQLite creates it last. -/
def CatalogTable.asWithoutRowid (table : CatalogTable) : CatalogTable :=
  let columns := table.columns.mapIdx fun position (column : CatalogColumn) =>
    if table.primaryKey.contains position then { column with notNull := true } else column
  { table with withoutRowid := true, rowidAlias := none, columns, primaryKey := table.primaryKey.eraseDups,
               uniqueBeforePrimary := if table.rowidAlias.isSome then table.uniqueKeys.length else table.uniqueBeforePrimary }

/-- The catalog column of a definition before its constraints apply: its name, its reported
type ({name}`reportedType`) and, in a {lit}`STRICT` table, its strict type
({name}`StrictType.ofReported`), which its affinity and its DEFAULT need (ADR 0014, D6). -/
def definedColumn (strict : Bool) (definition : Syntax.ColumnDefinition) : CatalogColumn :=
  let declaredType := reportedType definition.declaredType
  { name := definition.name, declaredType, strictType := if strict then StrictType.ofReported declaredType else none }

/-- The errors of a {lit}`STRICT` table's types (ADR 0014, D6; {lit}`sqlite3EndTable`), in
column order, or none: a column without a type is {name}`ExprError.missingDatatype`, and one
with a type that {name}`StrictType.ofReported` does not read is
{name}`ExprError.unknownDatatype`. A table that is not {lit}`STRICT` has none. -/
def strictTypeError (tableName : Identifier) (table : CatalogTable) : Option ExprError :=
  if !table.strict then none else
    table.columns.findSome? fun column => match column.declaredType, StrictType.ofReported column.declaredType with
      | _, some _ => none
      | none, none => some (.missingDatatype tableName column.name)
      | some written, none => some (.unknownDatatype tableName column.name written)

/-- The table with each primary-key column NOT NULL, with ABORT, when the table is
{lit}`STRICT` and the column is not the rowid alias and has no NOT NULL of its own, as
{lit}`sqlite3EndTable` does (R-40010-16873; checked natively with 3.51.0). For example,
{lit}`a TEXT PRIMARY KEY` of a {lit}`STRICT` table refuses NULL. A table that is not
{lit}`STRICT` is unchanged. -/
def CatalogTable.withStrictKeys (table : CatalogTable) : CatalogTable :=
  if !table.strict then table else
    { table with columns := table.columns.mapIdx fun position column =>
        if table.primaryKey.contains position && table.rowidAlias != some position && !column.notNull then
          { column with notNull := true, notNullAlgorithm := .abort }
        else column }

end Belay.Sqlite.Model
