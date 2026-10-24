import Belay.Sqlite.Model.ResolveDropValid
import Belay.Sqlite.Model.CatalogValidSet
import Belay.Sqlite.Model.CatalogValidAddColumn
import Belay.Sqlite.Model.ResolveTermsBelow
import Belay.Sqlite.Model.ResolveCreateTableValid
import Belay.Sqlite.Model.Resolution.AddColumn

set_option doc.verso true

/-! ADD COLUMN gives a valid catalog (ADR 0022, D3, slice 4): when the resolver of a script adds
a column to a table of a valid catalog, the catalog stays valid, and the default of the column fits
its strict type. The column has the name of its definition, and its CHECK constraints read below the
new width of the table ({lit}`columnChecks_below`). -/

namespace Belay.Sqlite.Model

/-- For every function on columns that keeps the name of the column, items, first column and last
column: if the function applied in turn over the items ({name}`List.foldlM` in {name}`Option`) gives the
last column, the last column has the name of the first. Proof sketch: induction over the items. -/
theorem foldlM_option_keeps_name {α : Type} {step : CatalogColumn → α → Option CatalogColumn}
    (keeps : ∀ column item result, step column item = some result → result.name = column.name) :
    ∀ (items : List α) (first last : CatalogColumn), items.foldlM step first = some last → last.name = first.name
  | [], first, last, ok => by simp only [List.foldlM_nil, Option.pure_def, Option.some.injEq] at ok; subst ok; rfl
  | item :: rest, first, last, ok => by
    simp only [List.foldlM_cons] at ok
    cases hstep : step first item with
    | none => simp [hstep] at ok
    | some next =>
      simp only [hstep] at ok
      exact (foldlM_option_keeps_name keeps rest next last ok).trans (keeps _ _ _ hstep)

/-- For every strictness, column definition and column: if {name}`addedColumn` gives the column, the
column has the name of the definition. Proof sketch: the column starts as {name}`definedColumn`, which
has that name, and no constraint changes the name ({name}`foldlM_option_keeps_name`). -/
theorem addedColumn_name {strict : Bool} {definition : Syntax.ColumnDefinition} {column : CatalogColumn}
    (ok : addedColumn strict definition = some column) : column.name = definition.name := by
  refine (foldlM_option_keeps_name ?_ _ _ _ ok).trans rfl
  intro column constraint result same
  cases constraint <;> simp only [Option.some.injEq, Option.map_eq_some_iff] at same
  all_goals first
    | (subst same; rfl)
    | (obtain ⟨_, _, rfl⟩ := same; rfl)

/-- For every column, CHECK constraints and foreign keys, {name}`strictDefaultFits` gives the same
answer for the column with the CHECK constraints and foreign keys replaced. Proof sketch: the strict
type and the read default do not depend on them, so both sides are equal by definition. -/
theorem strictDefaultFits_with (column : CatalogColumn) (checks : List CheckConstraint)
    (foreignKeys : List ForeignKey) :
    strictDefaultFits { column with checks, foreignKeys } = strictDefaultFits column := rfl

/-- For every valid catalog, table found by {name}`Catalog.findTable` at a position, definition,
column, CHECK constraints and foreign keys: if
* the name of the table is not reserved;
* the table has room for one more column under the column limit;
* the table has no column of the name of the definition ({name}`columnPosition`);
* the name of the definition is not a name of the rowid;
* {name}`addedColumn` gives the column from the definition and the strictness of the table;
* the CHECK constraints of the definition resolve ({name}`columnChecks`) to {lit}`checks`, over the scope
  of the table with the column appended;

then the catalog after {name}`Catalog.addColumn` of the column with these CHECK constraints and
foreign keys is valid. Proof sketch: the table with the column is supported
({name}`CatalogTable.supported_addColumn`); its CHECK constraints read below the new width
({name}`columnChecks_below`); {name}`Catalog.Valid.addColumn` ends the proof. -/
theorem Catalog.Valid.addColumnResolved {limits : Limits} {dqs : Bool} {catalog : Catalog} {position : Nat}
    {table : CatalogTable} {tableName : Identifier} {definition : Syntax.ColumnDefinition}
    {column : CatalogColumn} {checks : List CheckConstraint} {foreignKeys : List ForeignKey}
    (valid : catalog.Valid limits) (found : catalog.findTable tableName = some (position, table))
    (notReserved : ¬reservedName tableName = true)
    (fits : ¬table.columns.length + 1 > limits.columns)
    (fresh : ¬(columnPosition table.columns definition.name).isSome = true)
    (ordinary : ¬rowidName definition.name = true)
    (added : addedColumn table.strict definition = some column)
    (checked : columnChecks dqs (Scope.single tableName (table.columns ++ [column]) !table.withoutRowid)
      definition = .ok checks) :
    (catalog.addColumn position { column with checks, foreignKeys }).Valid limits := by
  have present := Catalog.tableAt_of_findTable found
  obtain ⟨object, atPosition, entry, folded⟩ := Catalog.findTable_some catalog _ position table found
  refine valid.addColumn present _ ?_ ?_
  · intro other same
    rw [atPosition] at same
    cases same
    simp only [reservedName, folded]
    simpa only [reservedName, Bool.not_eq_true] using notReserved
  · refine CatalogTable.supported_addColumn (valid.tableSupported present) (by omega) ?_ ?_ ?_
    · simpa [addedColumn_name added] using fresh
    · simpa [addedColumn_name added] using ordinary
    · intro check member
      have below := columnChecks_below (Scope.single_bounded tableName (table.columns ++ [column]) _) checked
      simpa [Resolved.Expr.readsBelow] using below check member

/-- For every context, valid catalog and successful resolution of ALTER TABLE ADD COLUMN, the catalog
after the resolution is valid. Proof sketch: split every branch of the resolver. A prepare error
returns the catalog, and a model restriction is no success. The branch that adds the column is
{name}`Catalog.Valid.addColumnResolved`. -/
theorem resolveAddColumn_valid (context : ResolveContext) (catalog after : Catalog) (tableName : Identifier)
    (definition : Syntax.ColumnDefinition) (statement : Resolved.Statement)
    (valid : catalog.Valid context.profile.limits)
    (ok : resolveAddColumn context catalog tableName definition = .ok (statement, after)) :
    after.Valid context.profile.limits := by
  unfold resolveAddColumn at ok
  simp only [prepareError, restrict] at ok
  repeat' split at ok
  all_goals first
    | (cases ok; exact valid)
    | (cases ok; done)
    | (cases ok
       exact Catalog.Valid.addColumnResolved valid (by assumption) (by assumption) (by assumption)
         (by assumption) (by assumption) (by assumption) (by assumption))

/-- For every context, catalog, table, definition, statement and column: if the resolution of
ALTER TABLE ADD COLUMN succeeds with a statement that adds the column at a position, the default
of the column fits its strict type ({name}`strictDefaultFits`). Proof sketch: split every branch of the
resolver. The branch that adds the column is the one that did not refuse
{lit}`!strictDefaultFits`, and the CHECK constraints and foreign keys do not change the answer
({name}`strictDefaultFits_with`). -/
theorem resolveAddColumn_strictDefaultFits (context : ResolveContext) (catalog after : Catalog)
    (tableName : Identifier) (definition : Syntax.ColumnDefinition) (position : Nat) (column : CatalogColumn)
    (ok : resolveAddColumn context catalog tableName definition = .ok (.addColumn position column, after)) :
    strictDefaultFits column = true := by
  unfold resolveAddColumn at ok
  simp only [prepareError, restrict] at ok
  repeat' split at ok
  all_goals first
    | (cases ok; done)
    | (simp only [Except.ok.injEq, Prod.mk.injEq, Resolved.Statement.addColumn.injEq] at ok
       obtain ⟨⟨_, rfl⟩, _⟩ := ok
       rw [strictDefaultFits_with]
       simpa using (by assumption : ¬(!strictDefaultFits _) = true))

end Belay.Sqlite.Model
