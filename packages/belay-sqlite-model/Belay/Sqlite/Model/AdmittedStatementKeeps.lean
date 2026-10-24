import Belay.Sqlite.Model.AdmittedCatalogStatement
import Belay.Sqlite.Model.AdmittedDistinctStatement
import Belay.Sqlite.Model.AdmittedRangeWideStatements
import Belay.Sqlite.Model.AdmittedShapedStatement
import Belay.Sqlite.Model.AdmittedStoredAliasedStatements
import Belay.Sqlite.Model.RunHoldsReady

set_option doc.verso true

/-! The statement theorems of the seven atoms of {lit}`Database.Admitted` in the form of
{lit}`StatementKeepsReady` (ADR 0022, D3, slice 4), the form that the run theorems use. The property is
the atom and the atoms that its theorem lists (decision 2 of the status file): "rows stored" lists "rows
wide", and "rows aliased" lists "catalog supported", whose condition (the catalog after the statement is
valid) is the condition of both. The atoms "rows shaped", "rowids distinct", "rowids in range" and "rows wide"
have no condition. The last theorem is the conjunction of all seven atoms. -/

namespace Belay.Sqlite.Model

/-- For the given limits and database: the catalog is valid under the limits ({name}`Catalog.Valid`). It is the
atom "catalog supported" of {name}`Database.Admitted`, with the limits of the profile. -/
abbrev Database.CatalogSupported (limits : Limits) (database : Database) : Prop := database.catalog.Valid limits

/-- For the given database: the rows are stored ({name}`Database.RowsStored`) and wide
({name}`Database.RowsWide`). It is the invariant of the run theorem of "rows stored", which lists "rows wide". -/
abbrev Database.RowsStoredWide (database : Database) : Prop := database.RowsStored ∧ database.RowsWide

/-- For the given limits and database: the rows are aliased ({name}`Database.RowsAliased`) and the catalog is valid
under the limits ({name}`Database.CatalogSupported`). It is the invariant of the run theorem of "rows aliased", which
lists "catalog supported". -/
abbrev Database.RowsAliasedSupported (limits : Limits) (database : Database) : Prop :=
  database.RowsAliased ∧ database.CatalogSupported limits

/-- The condition of "catalog supported" for a statement on a database and limits: the catalog after the
statement ({name}`Resolved.Statement.applyCatalog`) is valid under the limits. For a statement that is not
CREATE, ADD COLUMN or DROP it is the catalog of the database. -/
abbrev Resolved.Statement.AppliedValid (limits : Limits) (statement : Resolved.Statement) (database : Database) : Prop :=
  (statement.applyCatalog database.catalog).Valid limits

/-- The statement theorem of "catalog supported" in the form of {name}`StatementKeepsReady`. For every
limits: the property is {name}`Database.CatalogSupported`, and the condition is
{name}`Resolved.Statement.AppliedValid`. Proof sketch: {name}`runStatement_catalogSupported`. -/
theorem catalogSupported_statementKeeps (limits : Limits) :
    StatementKeepsReady (Database.CatalogSupported limits) (Resolved.Statement.AppliedValid limits) :=
  fun clock counters parameters statement _ valid applied _ =>
    runStatement_catalogSupported limits clock counters parameters statement valid applied

/-- The statement theorem of "rows shaped" in the form of {name}`StatementKeepsReady`, with no condition.
Proof sketch: {name}`runStatement_rowsShaped`. -/
theorem rowsShaped_statementKeeps : StatementKeepsReady Database.RowsShaped fun _ _ => True :=
  fun clock counters parameters statement _ shaped _ _ => runStatement_rowsShaped clock counters parameters statement shaped

/-- The statement theorem of "rowids distinct" in the form of {name}`StatementKeepsReady`, with no condition.
Proof sketch: {name}`runStatement_rowidsDistinct`. -/
theorem rowidsDistinct_statementKeeps : StatementKeepsReady Database.RowidsDistinct fun _ _ => True :=
  fun clock counters parameters statement _ distinct _ _ =>
    runStatement_rowidsDistinct clock counters parameters statement distinct

/-- The statement theorem of "rowids in range" in the form of {name}`StatementKeepsReady`, with no condition.
Proof sketch: {name}`runStatement_rowidsInRange`. -/
theorem rowidsInRange_statementKeeps : StatementKeepsReady Database.RowidsInRange fun _ _ => True :=
  fun clock counters parameters statement _ inRange _ ready =>
    runStatement_rowidsInRange clock counters parameters statement inRange ready

/-- The statement theorem of "rows wide" in the form of {name}`StatementKeepsReady`, with no condition.
Proof sketch: {name}`runStatement_rowsWide`. -/
theorem rowsWide_statementKeeps : StatementKeepsReady Database.RowsWide fun _ _ => True :=
  fun clock counters parameters statement _ wide _ ready => runStatement_rowsWide clock counters parameters statement wide ready

/-- The statement theorem of "rows stored" in the form of {name}`StatementKeepsReady`, with no condition. The
property is "rows stored" and "rows wide", the atom that its theorem lists. Proof sketch:
{name}`runStatement_rowsStored` and {name}`runStatement_rowsWide`. -/
theorem rowsStored_statementKeeps : StatementKeepsReady Database.RowsStoredWide fun _ _ => True :=
  fun clock counters parameters statement _ holds _ ready database kept =>
    ⟨runStatement_rowsStored clock counters parameters statement holds.1 holds.2 ready database kept,
      runStatement_rowsWide clock counters parameters statement holds.2 ready database kept⟩

/-- The statement theorem of "rows aliased" in the form of {name}`StatementKeepsReady`. For every limits: the
property is "rows aliased" and "the catalog is valid under the limits", the atom that its theorem lists,
and the condition is {name}`Resolved.Statement.AppliedValid`. Proof sketch: {name}`runStatement_rowsAliased`
and {name}`runStatement_catalogSupported`. -/
theorem rowsAliased_statementKeeps (limits : Limits) :
    StatementKeepsReady (Database.RowsAliasedSupported limits) (Resolved.Statement.AppliedValid limits) :=
  fun clock counters parameters statement _ holds applied ready database kept =>
    ⟨runStatement_rowsAliased limits clock counters parameters statement holds.1 holds.2 ready database kept,
      runStatement_catalogSupported limits clock counters parameters statement holds.2 applied database kept⟩

/-- The statement theorem of all seven atoms together, in the form of {name}`StatementKeepsReady`. For every
profile: the property is {name}`Database.Admitted` under the profile, and the condition is
{name}`Resolved.Statement.AppliedValid` for the limits of the profile. Proof sketch: the seven statement
theorems for the fields of the structure. -/
theorem admitted_statementKeeps (profile : Profile) :
    StatementKeepsReady (Database.Admitted profile) (Resolved.Statement.AppliedValid profile.limits) :=
  fun clock counters parameters statement _ admitted applied ready database kept =>
    ⟨runStatement_catalogSupported profile.limits clock counters parameters statement admitted.catalogSupported
        applied database kept,
      runStatement_rowsShaped clock counters parameters statement admitted.rowsShaped database kept,
      runStatement_rowidsDistinct clock counters parameters statement admitted.rowidsDistinct database kept,
      runStatement_rowidsInRange clock counters parameters statement admitted.rowidsInRange ready database kept,
      runStatement_rowsWide clock counters parameters statement admitted.rowsWide ready database kept,
      runStatement_rowsStored clock counters parameters statement admitted.rowsStored admitted.rowsWide ready
        database kept,
      runStatement_rowsAliased profile.limits clock counters parameters statement admitted.rowsAliased
        admitted.catalogSupported ready database kept⟩

end Belay.Sqlite.Model
