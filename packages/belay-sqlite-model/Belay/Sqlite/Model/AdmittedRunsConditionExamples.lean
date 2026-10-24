import Belay.Sqlite.Model.AdmittedSqlRunsCatalog
import Belay.Sqlite.Model.AdmittedSqlRunsRows
import Belay.Sqlite.Model.ScriptRunValid
import Belay.Sqlite.Model.AtomsConditionsOfLink
import Belay.Sqlite.Model.ResolveStatementApplied
import Belay.Sqlite.Model.AdmittedAtomsSchemaExamples
import Belay.Sqlite.Model.AdmittedAtomsCounterExamples
import Belay.Sqlite.Model.AdmittedAtomsEngineExamples

set_option doc.verso true

/-! Examples of the pieces of the run theorems of the Admitted atoms (ADR 0022, slice 4, part 3), each checked
by the kernel: the facts of the resolver on concrete statements ({lit}`Resolved.Statement.SchemaLink`), the
definitions of the invariants, the theorems of {lit}`runSql` applied to a script, and the conditions that
stay in the theorems of {lit}`runSqlFrom` and {lit}`runSql`, each with a run that breaks the atom when the
condition fails. -/

namespace Belay.Sqlite.Model.AdmittedRunsConditionExamples

open Belay.Sqlite.Model Syntax Resolution.Examples
open Belay.Sqlite.Model.AdmittedAtomsExamples (indexedCatalog)
open Belay.Sqlite.Model.AdmittedAtomsEngineExamples (emptyDatabase)
open Belay.Sqlite.Model.AdmittedAtomsCounterExamples (oneTable largestRowidTable insertCells)

/-- The resolver state of the catalog {name}`indexedCatalog`: a table {lit}`t` and its unique index {lit}`i`. -/
def indexedState : ResolveState := { catalog := indexedCatalog }

/-- The context of a script that runs, with the default profile. -/
def execution : ResolveContext := { profile := defaults, mode := .execution }

-- The link of a statement that needs none holds; the link of a DROP is the closure on the catalog.
example : (Resolved.Statement.begin).SchemaLink [] := trivial
example : (Resolved.Statement.drop [] none).SchemaLink indexedCatalog := Catalog.DropClosed.nil _
example : ¬ (Resolved.Statement.drop [0] none).SchemaLink indexedCatalog := fun closed =>
  absurd (closed.1 1 _ _ rfl rfl (by decide)) (by decide)

-- The link of ADD COLUMN is the fit of the default to the strict type; a column without a strict type fits.
example : (Resolved.Statement.addColumn 0 { name := name! "c", declaredType := some "INTEGER" }).SchemaLink indexedCatalog := by
  show strictDefaultFits _ = true
  decide +kernel

-- The resolver gives the link: DROP TABLE of {lit}`t` resolves to the drop of the table and its index, and the
-- theorem of the facts applies to every result of the resolution.
example : (match resolveStatement execution indexedState (.dropTable (name! "t") false) with
    | .ok (statement, _) => decide (statement = .drop [0, 1] none) | .error _ => false) = true := by decide +kernel
example (resolved : Resolved.Statement) (next : ResolveState)
    (ok : resolveStatement execution indexedState (.dropTable (name! "t") false) = .ok (resolved, next)) :
    resolved.SchemaLink indexedCatalog :=
  resolveStatement_schemaLink (limits := defaults.limits) execution indexedState next _ resolved (by decide +kernel) ok

-- The invariants. The empty database satisfies each; {name}`Database.AdmittedWith` adds an atom to the fields
-- of {name}`Database.Admitted`.
example : Database.CatalogSupported defaults.limits emptyDatabase := by decide +kernel
example : Database.RowsStoredWide ({} : Database) :=
  ⟨fun _ _ present => by simp [Database.table, Catalog.tableAt] at present,
    fun _ _ present => by simp [Database.table, Catalog.tableAt] at present⟩
example : Database.RowsAliasedSupported defaults.limits ({} : Database) :=
  ⟨(Database.valid_empty defaults).admitted.rowsAliased, (Database.valid_empty defaults).admitted.catalogSupported⟩
example : Database.AdmittedWith defaults Database.KeysUnique ({} : Database) :=
  ⟨(Database.valid_empty defaults).admitted, (Database.valid_empty defaults).unique⟩

-- The theorem of `runSql` applied: a script of one INSERT into the table of `emptyDatabase` passes the support
-- check, which the kernel decides, so the outcome keeps "rows shaped" and needs no run condition.
example : (runSql [(.insert 0 [[.value (.integer 1), .value (.text [97])]] [], [])] emptyDatabase).Holds
    Database.RowsShaped :=
  runSql_rowsShaped _ AdmittedAtomsEngineExamples.emptyDatabase_shaped (by decide +kernel)

-- A condition that stays: "rowids in range". The script of one INSERT after the largest rowid does not pass the
-- support check (the run is not ready), and the database after it has the rowid 2 ^ 63, out of range.

/-- The counterexample script of "rowids in range": the INSERT of a row into the table whose largest rowid is
{lit}`2 ^ 63 - 1`. -/
def pastLargest : List (Resolved.Statement × List Value) := [(insertCells [.value (.integer 2)], [])]
example : supportedSqlFrom 0 pastLargest { database := oneTable largestRowidTable } = false := by decide +kernel
example : ((runSql pastLargest (oneTable largestRowidTable)).database.rows.getD 0 []).map (·.rowid) =
    [2 ^ 63 - 1, 2 ^ 63] := by decide +kernel

-- A condition that stays: "catalog supported" needs {name}`Resolved.Statement.AppliedValid`. A DROP of the table
-- alone leaves the index without its table: the catalog after it is not valid, and the run ends with it.
example : ¬ (Resolved.Statement.drop [0] none).AppliedValid defaults.limits emptyDatabase := by
  show ¬ (Resolved.Statement.applyCatalog _ _).Valid _
  decide +kernel
example : ¬ (runSql [(.drop [0] none, [])] emptyDatabase).database.catalog.Valid defaults.limits := by
  decide +kernel

end Belay.Sqlite.Model.AdmittedRunsConditionExamples
