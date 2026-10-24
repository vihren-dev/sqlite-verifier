import Belay.Sqlite.Model.AddColumnFromValid
import Belay.Sqlite.Model.AdmittedStatementKeeps
import Belay.Sqlite.Model.ResolveStatementApplied
import Belay.Sqlite.Model.ValidAtomsTogether

set_option doc.verso true

/-! The conditions of the statement theorems of slices 2 and 3 for a statement that the resolver made
(ADR 0022, D3, slice 4). For an admitted database, a statement whose catalog after it is valid, and a
statement that meets {lit}`Resolved.Statement.SchemaLink`, the run condition of "keys unique" and the
conditions of "not null", "types fit" and "checks hold" hold. The run theorems of {lit}`runScriptFrom`
use them, so they ask for no hypothesis on the statements of the script. -/

namespace Belay.Sqlite.Model

/-- For every profile, admitted database and statement: if the catalog after the statement is valid under
the limits of the profile and the statement meets {name}`Resolved.Statement.SchemaLink` on the catalog of the
database, the statement meets its run condition for "keys unique" on the database
({name}`Resolved.Statement.RunCondition`). Proof sketch: CREATE INDEX has a supported index
({name}`Catalog.createIndex_supported`); ADD COLUMN meets {name}`Database.addColumnCondition_of_admitted`;
DROP meets the closure of the link, which gives {name}`Catalog.DropCondition`. -/
theorem Resolved.Statement.runCondition_of_link {profile : Profile} {database : Database}
    (admitted : database.Admitted profile) {statement : Resolved.Statement}
    (applied : statement.AppliedValid profile.limits database)
    (link : statement.SchemaLink database.catalog) : statement.RunCondition database := by
  cases statement with
  | createIndex target name index => exact Catalog.createIndex_supported applied
  | addColumn target column => exact database.addColumnCondition_of_admitted admitted target
  | drop positions rules => exact Catalog.DropClosed.dropCondition link
  | createTable | createTrigger | begin | commit | rollback | insert | update | upsert
  | delete | prepareError | query | setting => trivial

/-- For every profile, admitted database and statement: the statement meets its condition for "not null"
({name}`Resolved.Statement.NotNullCondition`) on the database. Proof sketch: the only condition is
{name}`Database.RowsWideAt` for ADD COLUMN, which {name}`Database.rowsWideAt_of_admitted` gives. -/
theorem Resolved.Statement.notNullCondition_of_admitted {profile : Profile} {database : Database}
    (admitted : database.Admitted profile) (statement : Resolved.Statement) :
    statement.NotNullCondition database := by
  cases statement with
  | addColumn target column => exact database.rowsWideAt_of_admitted admitted target
  | createTable | createIndex | createTrigger | drop | begin | commit | rollback | insert
  | update | upsert | delete | prepareError | query | setting => trivial

/-- For every profile, admitted database and statement that meets {name}`Resolved.Statement.SchemaLink` on the
catalog of the database: the statement meets its condition for "types fit"
({name}`Resolved.Statement.TypesFitCondition`) on the database. Proof sketch: for ADD COLUMN the rows are wide
({name}`Database.rowsWideAt_of_admitted`) and the link gives the strict default
({name}`Database.strictDefaultFitsAt_of_fits`). -/
theorem Resolved.Statement.typesFitCondition_of_link {profile : Profile} {database : Database}
    (admitted : database.Admitted profile) {statement : Resolved.Statement}
    (link : statement.SchemaLink database.catalog) : statement.TypesFitCondition database := by
  cases statement with
  | addColumn target column =>
    exact ⟨database.rowsWideAt_of_admitted admitted target, Database.strictDefaultFitsAt_of_fits link⟩
  | createTable | createIndex | createTrigger | drop | begin | commit | rollback | insert
  | update | upsert | delete | prepareError | query | setting => trivial

/-- For every profile, admitted database and statement: the statement meets its condition for "checks hold"
({name}`Resolved.Statement.ChecksHoldCondition`) on the database. Proof sketch: for ADD COLUMN the rows are
wide ({name}`Database.rowsWideAt_of_admitted`) and the valid catalog gives the reading of the CHECKs
({name}`Database.checksReadBelowAt_of_valid`). -/
theorem Resolved.Statement.checksHoldCondition_of_admitted {profile : Profile} {database : Database}
    (admitted : database.Admitted profile) (statement : Resolved.Statement) :
    statement.ChecksHoldCondition database := by
  cases statement with
  | addColumn target column =>
    exact ⟨database.rowsWideAt_of_admitted admitted target,
      Database.checksReadBelowAt_of_valid admitted.catalogSupported target⟩
  | createTable | createIndex | createTrigger | drop | begin | commit | rollback | insert
  | update | upsert | delete | prepareError | query | setting => trivial

/-- For every profile, admitted database and statement that meets the hypotheses of
{name}`Resolved.Statement.runCondition_of_link`: the statement meets the conditions of the four atoms together
({name}`Resolved.Statement.AtomsCondition`) on the database. Proof sketch: the four conditions above. -/
theorem Resolved.Statement.atomsCondition_of_link {profile : Profile} {database : Database}
    (admitted : database.Admitted profile) {statement : Resolved.Statement}
    (applied : statement.AppliedValid profile.limits database)
    (link : statement.SchemaLink database.catalog) : statement.AtomsCondition database :=
  ⟨statement.runCondition_of_link admitted applied link, statement.notNullCondition_of_admitted admitted,
    statement.typesFitCondition_of_link admitted link, statement.checksHoldCondition_of_admitted admitted⟩

end Belay.Sqlite.Model
