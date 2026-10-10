import Belay.Sqlite.ResolvePrepareSpec

set_option doc.verso true

/-! The prepare-error rule for ADD COLUMN and CREATE INDEX, and the transaction rule.
See {lit}`Belay.Sqlite.ResolvePrepareSpec` for the prepare-error rule. -/

namespace Belay.Sqlite

/-- For every ADD COLUMN whose resolution is a prepare error that names a catalog
object: the error is {lit}`no such table` for the statement's table, no table has the
folded name, and the catalog is unchanged. -/
theorem resolveAddColumn_named (context : ResolveContext) (catalog after : Catalog) (index : Nat)
    (tableName : String) (definition : Syntax.ColumnDefinition) (error : PrepareError)
    (named : error.namesObject = true)
    (ok : resolveAddColumn context catalog index tableName definition = .ok (.prepareError error, after)) :
    error = .noSuchTable tableName ∧ catalog.findTable tableName = none ∧ after = catalog := by
  unfold resolveAddColumn at ok
  simp only [prepareError, restrict] at ok
  repeat' split at ok
  all_goals (try (cases ok; done))
  all_goals cases ok
  all_goals first
    | (simp [PrepareError.namesObject] at named; done)
    | (simp_all; done)

/-- For every ADD COLUMN: when no table has the folded name, the resolution is
{lit}`no such table`, and the catalog is unchanged. -/
theorem resolveAddColumn_missing (context : ResolveContext) (catalog : Catalog) (index : Nat)
    (tableName : String) (definition : Syntax.ColumnDefinition)
    (missing : catalog.findTable tableName = none) :
    resolveAddColumn context catalog index tableName definition =
      .ok (.prepareError (.noSuchTable tableName), catalog) := by
  unfold resolveAddColumn
  simp [missing, prepareError]

/-- The duplicate-column rule of ADD COLUMN ({lit}`sqlite3AddColumn`): for every
table that the folded name finds, whose name SQLite does not reserve and with fewer
columns than the profile limit, the resolution is {lit}`duplicate column name` exactly
when a column of the table has the folded name of the new column. -/
theorem resolveAddColumn_duplicate (context : ResolveContext) (catalog : Catalog) (index : Nat)
    (tableName : String) (definition : Syntax.ColumnDefinition) (position : Nat) (table : CatalogTable)
    (found : catalog.findTable tableName = some (position, table))
    (notReserved : reservedName tableName = false)
    (room : table.columns.length + 1 ≤ context.profile.limits.columns) :
    resolveAddColumn context catalog index tableName definition =
        .ok (.prepareError (.duplicateColumn definition.name), catalog) ↔
      (columnPosition table.columns definition.name).isSome = true := by
  unfold resolveAddColumn
  have room' : ¬ table.columns.length + 1 > context.profile.limits.columns := by omega
  simp only [found, notReserved, Bool.false_eq_true, ite_false, room', prepareError]
  by_cases used : (columnPosition table.columns definition.name).isSome = true
  · simp [used]
  · simp only [used]
    repeat' split
    all_goals simp_all [restrict]

/-- For every CREATE INDEX of a catalog description whose resolution is a prepare error
that names a catalog object: either no table has the folded table name and the error
is {lit}`no such table`, or an object has the folded index name; and the catalog is
unchanged. -/
theorem resolveCreateIndex_named (context : ResolveContext) (catalog after : Catalog) (index : Nat)
    (name : String) (unique : Bool) (tableName : String) (columns : List String)
    (error : PrepareError) (named : error.namesObject = true)
    (ok : resolveCreateIndex context catalog index name unique tableName columns = .ok (.prepareError error, after)) :
    ((catalog.findTable tableName = none ∧ error = .noSuchTable tableName) ∨
      (catalog.find name).isSome = true) ∧ after = catalog := by
  unfold resolveCreateIndex at ok
  simp only [prepareError, restrict] at ok
  repeat' split at ok
  all_goals (try (cases ok; done))
  all_goals cases ok
  all_goals first
    | (simp [PrepareError.namesObject] at named; done)
    | (simp_all; done)
    | (rename_i cause; simp [keyPositions_error _ _ _ cause] at named; done)

/-- For every CREATE INDEX of a catalog description: when no table has the folded
table name, the resolution is {lit}`no such table`, and the catalog is unchanged. -/
theorem resolveCreateIndex_missing (context : ResolveContext) (catalog : Catalog) (index : Nat)
    (name : String) (unique : Bool) (tableName : String) (columns : List String)
    (description : context.mode = .description) (missing : catalog.findTable tableName = none) :
    resolveCreateIndex context catalog index name unique tableName columns =
      .ok (.prepareError (.noSuchTable tableName), catalog) := by
  unfold resolveCreateIndex
  simp [description, missing, prepareError]

/-- For every CREATE INDEX of a catalog description, on a table that the folded name
finds, where SQLite reserves neither name: when an object has the folded index name,
the resolution is a prepare error that names a catalog object. -/
theorem resolveCreateIndex_used (context : ResolveContext) (catalog : Catalog) (index : Nat)
    (name : String) (unique : Bool) (tableName : String) (columns : List String)
    (position : Nat) (table : CatalogTable) (description : context.mode = .description)
    (found : catalog.findTable tableName = some (position, table))
    (tableAllowed : reservedName tableName = false) (nameAllowed : reservedName name = false)
    (used : (catalog.find name).isSome = true) :
    ∃ error, error.namesObject = true ∧
      resolveCreateIndex context catalog index name unique tableName columns = .ok (.prepareError error, catalog) := by
  unfold resolveCreateIndex
  simp only [description, found, tableAllowed, nameAllowed, Bool.false_eq_true, ite_false, prepareError]
  cases hfind : catalog.find name with
  | none => simp [hfind] at used
  | some result =>
    obtain ⟨_, object⟩ := result
    cases object with
    | mk objectName entry => cases entry <;> simp [PrepareError.namesObject]

end Belay.Sqlite
