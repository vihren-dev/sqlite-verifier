import Belay.Sqlite.Resolution.Resolve

set_option doc.verso true

/-! The resolution of a schema and a script. The schema statements describe a
starting catalog, as the schema text that SQLite keeps in {lit}`sqlite_schema`
does. The script statements then resolve against that catalog, as statements that
the execution semantics runs. -/

namespace Belay.Sqlite

/-- Why a schema and a script have no resolution. SQLite refuses to prepare a
schema statement, or the model does not describe a schema or script statement. -/
inductive ScriptIssue where
  /-- The model does not describe this schema statement. -/
  | schemaRestricted (restriction : Restriction)
  /-- SQLite refuses to prepare the schema statement at this zero-based index. -/
  | schemaPrepareError (statement : Nat) (error : PrepareError)
  /-- The model does not describe this script statement. -/
  | scriptRestricted (restriction : Restriction)
  deriving Repr, DecidableEq

/-- A schema and a script with their resolution. The catalogs and the resolved
statements are results of {name}`resolve`; the profile and the statements are the
inputs. -/
structure ResolvedScript where
  /-- The execution profile. -/
  profile : Profile
  /-- The schema statements as written. -/
  schema : List Syntax.Statement
  /-- The catalog that the schema statements describe. -/
  startCatalog : Catalog
  /-- The script statements as written. -/
  script : List Syntax.Statement
  /-- The script statements after resolution against the starting catalog. -/
  resolved : List Resolved.Statement
  /-- The catalog after every script statement succeeds. -/
  nextCatalog : Catalog
  deriving Repr, DecidableEq

/-- Whether a schema statement can describe a catalog: CREATE TABLE or CREATE INDEX. -/
def Syntax.Statement.describesCatalog : Syntax.Statement → Bool
  | .createTable .. | .createIndex .. => true
  | .addColumn .. | .begin | .commit | .rollback | .insert .. | .update .. | .delete .. | .select .. | .returning .. =>
    false

/-- The first schema statement that cannot describe a catalog, as a restriction. -/
def schemaStatementRestriction (schema : List Syntax.Statement) : Option Restriction :=
  (findPosition (!·.describesCatalog) schema).map fun (index, _) =>
    { statement := index, path := [], kind := .schemaStatement }

/-- The prepare error of a resolved statement, if it is one. -/
def Resolved.Statement.prepareError? : Resolved.Statement → Option PrepareError
  | .prepareError error => some error
  | .createTable .. | .createIndex .. | .addColumn .. | .begin | .commit | .rollback
  | .insert .. | .upsert .. | .update .. | .delete .. | .query _ | .clocked .. => none

/-- The zero-based index and error of the first prepare error in a list of
resolved statements, from a starting index. -/
def firstPrepareErrorFrom (index : Nat) : List Resolved.Statement → Option (Nat × PrepareError)
  | [] => none
  | statement :: rest => match statement.prepareError? with
    | some error => some (index, error)
    | none => firstPrepareErrorFrom (index + 1) rest

/-- Resolve a schema, then a script. The schema statements resolve in description
mode against the empty catalog; each must be CREATE TABLE or CREATE INDEX and must
prepare without an error. The script statements resolve in execution mode against
the resulting catalog; a prepare error there stays in the resolved statements. -/
def resolveSchemaAndScript (profile : Profile) (schema script : List Syntax.Statement) :
    Except ScriptIssue ResolvedScript :=
  match schemaStatementRestriction schema with
  | some restriction => .error (.schemaRestricted restriction)
  | none =>
    match resolve { profile, mode := .description } [] schema with
    | .restricted restriction => .error (.schemaRestricted restriction)
    | .resolved described startCatalog =>
      match firstPrepareErrorFrom 0 described with
      | some (index, error) => .error (.schemaPrepareError index error)
      | none =>
        match resolve { profile, mode := .execution } startCatalog script with
        | .restricted restriction => .error (.scriptRestricted restriction)
        | .resolved resolved nextCatalog => .ok { profile, schema, startCatalog, script, resolved, nextCatalog }

end Belay.Sqlite
