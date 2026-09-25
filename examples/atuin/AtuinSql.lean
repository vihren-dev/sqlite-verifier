import AtuinFacts
import AtuinWrites

/-! The explicit five-statement SQL script is checked for arbitrary admitted data. -/
namespace AtuinSql
open SqliteVerifier AtuinMetadata

/-- These ordinary AST nodes are bound to the independently parsed SQL file below. -/
def script : List Statement := [.beginTransaction, .addColumn "history" SchemaBinding.shell,
  .insert "_sqlx_migrations" (SchemaBinding.metadata.columns.map Column.name) (values (-1)),
  .commit, .update "_sqlx_migrations" "execution_time" (.integer 1000000)
    "version" AtuinCatalog.targetVersion]
/-- No statement or engine selection is supplied by an untrusted proof alias. -/
theorem inputs_bound : Generated.script = script ∧ Generated.profile = .sqlite346 := by
  constructor
  · decide +kernel
  · rfl
/-- The final data retains all old rows and gives the added metadata its explicit elapsed value. -/
def result (database : Database) (history metadata : Table) : Database :=
  (database.set "history" (history.appendColumns [SchemaBinding.shell])).set
    "_sqlx_migrations" (extended metadata 1000000)

/-- Overwriting a table twice leaves exactly the final replacement. -/
theorem replace_twice (database : Database) (name : String) (first second : Table) :
    (database.set name first).set name second = database.set name second := by
  funext other
  by_cases equal : other = name <;> simp [Database.set, equal]

/-- ADD does not read old cell values or impose an application history cardinality. -/
theorem add_step (present : database "history" = some history)
    (columns : history.columns = SchemaBinding.history.columns) (position : Nat) :
    step (.addColumn "history" SchemaBinding.shell) database position =
      .success (database.set "history" (history.appendColumns [SchemaBinding.shell])) := by
  have size : ¬history.columns.length ≥ maximumColumns := by rw [columns]; decide +kernel
  have fresh : history.columns.any (fun old => old.name == SchemaBinding.shell.name) = false := by
    rw [columns]; decide +kernel
  have nameAllowed : supportedTableName "history" = true := by decide +kernel
  have columnAllowed : supportedColumn SchemaBinding.shell = true := by decide +kernel
  have plain : SchemaBinding.shell.plain = true := by decide +kernel
  simp only [step, nameAllowed, columnAllowed, plain, Bool.true_and, Bool.not_true,
    Bool.false_eq_true, ↓reduceIte, present, size, fresh]

/-- All reached literal writes are supported and the explicit COMMIT closes the transaction. -/
theorem executes (historyStored : database "history" = some history)
    (historyColumns : history.columns = SchemaBinding.history.columns)
    (metadataStored : database "_sqlx_migrations" = some metadata)
    (metadataColumns : metadata.columns = SchemaBinding.metadata.columns)
    (metadataProperties : metadata.properties = SchemaBinding.metadata.properties)
    (invariant : AtuinCatalog.Invariant AtuinCatalog.prior metadata)
    (bounded : validRowid (LiteralData.nextRowid metadata.rows)) :
    runSql script database = .success (result database history metadata) ∧
    SupportedSql SchemaBinding.start script database := by
  let historyDb := database.set "history" (history.appendColumns [SchemaBinding.shell])
  have catalog : historyDb "_sqlx_migrations" = some metadata := by
    simpa [historyDb, Database.set] using metadataStored
  have inserted : LiteralData.constraints (extended metadata (-1)) = true :=
    extended_constraints metadataColumns metadataProperties invariant
  have updated := AtuinWrites.updated metadataColumns invariant.2
  have finalConstraints : LiteralData.constraints (extended metadata 1000000) = true :=
    extended_constraints metadataColumns metadataProperties invariant
  have insertReady := AtuinWrites.insert_ready metadataColumns metadataProperties invariant bounded
  have updateReady := AtuinWrites.update_ready metadataColumns metadataProperties invariant
  have add := add_step historyStored historyColumns 1
  have written : (historyDb.set "_sqlx_migrations" (extended metadata (-1)))
      "_sqlx_migrations" = some (extended metadata (-1)) := by simp [Database.set]
  dsimp only [historyDb] at catalog written
  constructor
  · simp only [runSql, script, runSqlFrom, advance, literalStep, add, catalog, written,
      show LiteralData.inserted metadata (values (-1)) = extended metadata (-1) from rfl,
      inserted, updated, finalConstraints, ↓reduceIte, SqlState.finish, replace_twice]
    rfl
  · refine ⟨by rfl, ?_⟩
    simp only [script, supportedSqlFrom, statementReady, advance, literalStep, add,
      catalog, written, show LiteralData.inserted metadata (values (-1)) = extended metadata (-1) from rfl,
      inserted, updated, finalConstraints, insertReady, updateReady, ↓reduceIte,
      Option.all_some, Bool.true_and]

/-- Both writes replace only metadata rows; all generated declarations and indexes survive. -/
theorem conforms (before : Conforms SchemaBinding.start database)
    (historyStored : database "history" = some history)
    (metadataStored : database "_sqlx_migrations" = some metadata)
    (metadataColumns : metadata.columns = SchemaBinding.metadata.columns)
    (bounded : validRowid (LiteralData.nextRowid metadata.rows)) :
    Conforms SchemaBinding.next (result database history metadata) := by
  have add := before.appendAt historyStored AtuinFacts.next_valid (by
    have shape := (before.2 "history").1
    have columns : history.columns = SchemaBinding.history.columns := by
      rw [historyStored] at shape
      change some history.columns = some SchemaBinding.history.columns at shape
      exact Option.some.inj shape
    rw [columns]
    decide +kernel)
  have stored : (database.set "history" (history.appendColumns [SchemaBinding.shell]))
      "_sqlx_migrations" = some metadata := by simpa [Database.set] using metadataStored
  have valid := ((before.2 "_sqlx_migrations").2 metadata metadataStored).1
  exact add.replaceRows stored rfl rfl (valid.inserted bounded (by rw [metadataColumns]; rfl))

/-- The actual old history survives and shell cells come from the nullable extension. -/
theorem history_stored : result database history metadata "history" =
    some (history.appendColumns [SchemaBinding.shell]) := by simp [result, Database.set]
/-- The actual resulting catalog, rather than a candidate observation, contains the new row. -/
theorem metadata_stored : result database history metadata "_sqlx_migrations" =
    some (extended metadata 1000000) := by simp [result, Database.set]

end AtuinSql
