import Belay.Sqlite.Model.Resolution.Resolve

set_option doc.verso true

/-! The resolution of a schema and a script. The schema statements describe a
starting catalog, as the schema text that SQLite keeps in {lit}`sqlite_schema`
does. The script statements then resolve against that catalog, as statements that
the execution semantics runs. -/

namespace Belay.Sqlite.Model

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
  deriving Repr, BEq

/-- Whether a schema statement can describe a catalog: CREATE TABLE, CREATE INDEX or CREATE
TRIGGER. -/
def Syntax.Statement.describesCatalog : Syntax.Statement → Bool
  | .createTable .. | .createIndex .. | .createTrigger .. => true
  | .addColumn .. | .dropTable .. | .dropIndex .. | .dropTrigger .. | .begin | .commit | .rollback | .insert .. | .update ..
  | .delete .. | .select .. | .pragma _ => false

/-- The first schema statement that cannot describe a catalog, as a restriction. -/
def schemaStatementRestriction (schema : List Syntax.Statement) : Option Restriction :=
  (findPosition (!·.describesCatalog) schema).map fun (index, _) =>
    { statement := index, path := [], kind := .schemaStatement }

/-- The prepare error of a resolved statement, if it is one. -/
def Resolved.Statement.prepareError? : Resolved.Statement → Option PrepareError
  | .prepareError error => some error
  | .createTable .. | .createIndex .. | .createTrigger .. | .addColumn .. | .drop .. | .begin | .commit
  | .rollback | .insert .. | .upsert .. | .update .. | .delete .. | .query .. | .setting .. => none

/-- Whether two triggers of a schema may both fire for one write, so that their order matters:
the same folded table name, the same time and the same kind of event. -/
def CatalogTrigger.overlaps (first second : CatalogTrigger) : Bool :=
  first.table.sameName second.table && first.time == second.time && match first.event, second.event with
    | .insert, .insert | .delete, .delete | .update _, .update _ => true
    | .insert, .update _ | .insert, .delete | .update _, .insert | .update _, .delete | .delete, .insert
    | .delete, .update _ => false

/-- The first statement of a schema, from a starting index, that creates a trigger which
overlaps a trigger of an earlier statement ({name}`CatalogTrigger.overlaps`), as the
restriction {name}`RestrictionKind.schemaTriggerOrder`: a case record lists the schema in name
order, so the order in which SQLite runs the two is not known (ADR 0018, D5). -/
def schemaTriggerRestriction (index : Nat) (earlier : List CatalogTrigger) : List Syntax.Statement → Option Restriction
  | [] => none
  | statement :: rest => match statement with
    | .createTrigger _ _ time event table condition body =>
      let trigger : CatalogTrigger := { table, time, event, condition, body }
      if earlier.any trigger.overlaps then some { statement := index, path := [], kind := .schemaTriggerOrder }
      else schemaTriggerRestriction (index + 1) (earlier ++ [trigger]) rest
    | .createTable .. | .createIndex .. | .addColumn .. | .dropTable .. | .dropIndex .. | .dropTrigger .. | .begin
    | .commit | .rollback | .insert .. | .update .. | .delete .. | .select .. | .pragma _ =>
      schemaTriggerRestriction (index + 1) earlier rest

/-- The zero-based index and error of the first prepare error in a list of
resolved statements, from a starting index. -/
def firstPrepareErrorFrom (index : Nat) : List Resolved.Statement → Option (Nat × PrepareError)
  | [] => none
  | statement :: rest => match statement.prepareError? with
    | some error => some (index, error)
    | none => firstPrepareErrorFrom (index + 1) rest

/-- Resolve a schema to the catalog that it describes. The schema statements resolve in
description mode against the empty catalog; each must be CREATE TABLE, CREATE INDEX or CREATE
TRIGGER and must prepare without an error. Two triggers that overlap in the schema are a
restriction ({name}`schemaTriggerRestriction`). The result is never
{name}`ScriptIssue.scriptRestricted`. -/
def resolveSchema (profile : Profile) (schema : List Syntax.Statement) : Except ScriptIssue Catalog :=
  match schemaStatementRestriction schema <|> schemaTriggerRestriction 0 [] schema with
  | some restriction => .error (.schemaRestricted restriction)
  | none =>
    match resolve { profile, mode := .description } [] schema with
    | .restricted restriction => .error (.schemaRestricted restriction)
    | .resolved described startCatalog =>
      match firstPrepareErrorFrom 0 described with
      | some (index, error) => .error (.schemaPrepareError index error)
      | none => .ok startCatalog

/-- Resolve a schema ({name}`resolveSchema`), then a script. The script statements resolve in
execution mode against the catalog of the schema; a prepare error there stays in the resolved
statements. -/
def resolveSchemaAndScript (profile : Profile) (schema script : List Syntax.Statement) :
    Except ScriptIssue ResolvedScript := do
  let startCatalog ← resolveSchema profile schema
  match resolve { profile, mode := .execution } startCatalog script with
  | .restricted restriction => .error (.scriptRestricted restriction)
  | .resolved resolved nextCatalog => .ok { profile, schema, startCatalog, script, resolved, nextCatalog }

end Belay.Sqlite.Model
