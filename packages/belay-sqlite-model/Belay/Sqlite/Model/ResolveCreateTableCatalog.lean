import Belay.Sqlite.Model.ResolveCreateTableValid
import Belay.Sqlite.Model.CatalogValidLaws

set_option doc.verso true

/-! CREATE TABLE gives a valid catalog (ADR 0022, D3, slice 4): when the resolver of a script
appends a table to a valid catalog, the catalog stays valid. The proof follows the stages of
{lit}`resolveCreateTable`: the definitions and the table constraints give a draft
({lit}`ResolveDefinitionsShaped`, {lit}`ResolveTableConstraintsShaped`), the options of the table keep
its shape, and the CHECK constraints and the generated columns end it ({lit}`ResolveCreateTableValid`). -/

namespace Belay.Sqlite.Model

/-- For every strictness, the table without columns, keys and rowid alias is a draft. Proof sketch: every clause of {name}`CatalogTable.Draft` is about the members of an empty list, or about the rowid alias, which is none.  -/
theorem CatalogTable.draft_empty (strict : Bool) : ({ columns := [], strict } : CatalogTable).Draft :=
  ⟨⟨by simp, by simp, by simp, fun _ found => by cases found⟩, rfl, by simp [AnyDeclared]⟩

/-- For every limits, name, definitions, table constraints and strictness: if the definitions and then the
table constraints give a table, the table is a draft that has the names of the definitions and at most
as many columns as the limit. Proof sketch: {name}`addDefinitions_draft` and
{name}`addTableConstraints_draft` from the table without columns. -/
theorem CatalogTable.draft_of_built {limit : Nat} {name : Identifier} {strict : Bool}
    {definitions : List Syntax.ColumnDefinition} {constraints : List Syntax.TableConstraint} {table : CatalogTable}
    (built : (addDefinitions limit name { columns := [], strict } definitions >>=
      (addTableConstraints name · constraints)) = .ok table) :
    table.Draft ∧ table.columns.map (·.name) = definitions.map (·.name) ∧ table.columns.length ≤ limit := by
  obtain ⟨defined, hdefined, hconstraints⟩ := exceptBind_eq_ok.mp built
  obtain ⟨draft, within, names, _⟩ := addDefinitions_draft (CatalogTable.draft_empty strict) (by simp) hdefined
  obtain ⟨final, finalNames⟩ := addTableConstraints_draft draft hconstraints
  refine ⟨final, ?_, ?_⟩
  · rw [finalNames, names]; simp
  · have := congrArg List.length finalNames
    simp only [List.length_map] at this
    omega

/-- For every valid catalog and every table that CREATE TABLE builds: if the name is not used, is not
reserved, and the table is supported, the catalog with the table appended is valid. The stages before
the table are facts about the table {lit}`first`, which the options of the table give, and the CHECK
constraints and generated columns that follow. Proof sketch: {name}`Catalog.Valid.append`, with the
table supported by {name}`CatalogTable.supported_of_finished`. -/
theorem Catalog.Valid.createTable {context : ResolveContext} {catalog : Catalog} {name : Identifier}
    {definitions : List Syntax.ColumnDefinition} {constraints : List Syntax.TableConstraint}
    {first second third : CatalogTable} (valid : catalog.Valid context.profile.limits)
    (execution : context.mode = .execution) (fresh : catalog.find name = none)
    (notReserved : ¬(reservedName name &&
      !(context.mode == Mode.description && statisticsTable name definitions constraints)) = true)
    (shaped : first.Shaped) (aliasKind : first.rowidAlias.isSome = true → first.withoutRowid = false)
    (named : first.columns.map (·.name) = definitions.map (·.name))
    (within : first.columns.length ≤ context.profile.limits.columns)
    (notGenerated : ¬(first.columns.all fun column => column.generated.isSome) = true)
    (ordinaryNames : (definitions.any fun definition => rowidName definition.name) = false)
    (checked : resolveTableChecks context.profile.dqsDdl (Scope.single name first.columns !first.withoutRowid)
      first definitions constraints = .ok second)
    (generated : resolveGeneratedColumns context.profile.dqsDdl (Scope.single name second.columns false) second
      definitions = .ok third) :
    (catalog.createTable name third).Valid context.profile.limits := by
  have ordinary : reservedName name = false := by simpa [execution] using notReserved
  refine Valid.append valid { name, entry := .table third } (fun _ => fresh) ?_
  simp only [CatalogObject.supported, ordinary, Bool.not_false, Bool.true_or, Bool.and_true]
  exact CatalogTable.supported_of_finished shaped aliasKind named within notGenerated ordinaryNames checked generated

/-- For every context in execution mode, valid catalog, name, definitions and table constraints: if
* the name is not found in the catalog and is not reserved;
* the definitions and then the table constraints give a table ({lit}`table`);
* not every column of {name}`CatalogTable.asWithoutRowid` of the table is generated;
* the CHECK constraints resolve for that table to {lit}`second`, and the generated columns of
  {lit}`second` resolve to {lit}`third`;
* no definition has the name of the rowid;

then the catalog with {lit}`third` appended ({name}`Catalog.createTable`) is valid. Proof sketch: the
table is a draft ({name}`CatalogTable.draft_of_built`), its WITHOUT ROWID form is shaped
({name}`CatalogTable.asWithoutRowid_shaped`), and {name}`Catalog.Valid.createTable` ends the proof. -/
theorem Catalog.Valid.createTable_withoutRowid {context : ResolveContext} {catalog : Catalog} {name : Identifier}
    {strict : Bool} {definitions : List Syntax.ColumnDefinition} {constraints : List Syntax.TableConstraint}
    {table second third : CatalogTable} (valid : catalog.Valid context.profile.limits)
    (execution : context.mode = .execution) (fresh : catalog.find name = none)
    (notReserved : ¬(reservedName name &&
      !(context.mode == Mode.description && statisticsTable name definitions constraints)) = true)
    (built : (addDefinitions context.profile.limits.columns name { columns := [], strict } definitions >>=
      (addTableConstraints name · constraints)) = .ok table)
    (notGenerated : ¬(table.asWithoutRowid.columns.all fun column => column.generated.isSome) = true)
    (checked : resolveTableChecks context.profile.dqsDdl
      (Scope.single name table.asWithoutRowid.columns !table.asWithoutRowid.withoutRowid) table.asWithoutRowid
      definitions constraints = .ok second)
    (generated : resolveGeneratedColumns context.profile.dqsDdl (Scope.single name second.columns false) second
      definitions = .ok third)
    (ordinaryNames : ¬(definitions.any fun definition => rowidName definition.name) = true) :
    (catalog.createTable name third).Valid context.profile.limits := by
  obtain ⟨draft, named, within⟩ := CatalogTable.draft_of_built built
  have layouts := table.asWithoutRowid_layouts
  refine Valid.createTable valid execution fresh notReserved (CatalogTable.asWithoutRowid_shaped draft)
    (fun some => by simp [CatalogTable.asWithoutRowid] at some) ((names_eq_of_layout layouts).trans named)
    (by have := congrArg List.length layouts; simp only [List.length_map] at this; omega) notGenerated
    (by simpa using ordinaryNames)
    checked generated

/-- For every context in execution mode, valid catalog, name, definitions and table constraints: if
* the name is not found in the catalog and is not reserved;
* the definitions and then the table constraints give a table ({lit}`table`);
* not every column of {name}`CatalogTable.withStrictKeys` of the table is generated;
* the CHECK constraints resolve for that table to {lit}`second`, and the generated columns of
  {lit}`second` resolve to {lit}`third`;
* no definition has the name of the rowid;

then the catalog with {lit}`third` appended ({name}`Catalog.createTable`) is valid. Proof sketch: the
table is a draft ({name}`CatalogTable.draft_of_built`), its form with strict keys is shaped
({name}`CatalogTable.withStrictKeys_shaped`), and {name}`Catalog.Valid.createTable` ends the proof. -/
theorem Catalog.Valid.createTable_ordinary {context : ResolveContext} {catalog : Catalog} {name : Identifier}
    {strict : Bool} {definitions : List Syntax.ColumnDefinition} {constraints : List Syntax.TableConstraint}
    {table second third : CatalogTable} (valid : catalog.Valid context.profile.limits)
    (execution : context.mode = .execution) (fresh : catalog.find name = none)
    (notReserved : ¬(reservedName name &&
      !(context.mode == Mode.description && statisticsTable name definitions constraints)) = true)
    (built : (addDefinitions context.profile.limits.columns name { columns := [], strict } definitions >>=
      (addTableConstraints name · constraints)) = .ok table)
    (notGenerated : ¬(table.withStrictKeys.columns.all fun column => column.generated.isSome) = true)
    (checked : resolveTableChecks context.profile.dqsDdl
      (Scope.single name table.withStrictKeys.columns !table.withStrictKeys.withoutRowid) table.withStrictKeys
      definitions constraints = .ok second)
    (generated : resolveGeneratedColumns context.profile.dqsDdl (Scope.single name second.columns false) second
      definitions = .ok third)
    (ordinaryNames : ¬(definitions.any fun definition => rowidName definition.name) = true) :
    (catalog.createTable name third).Valid context.profile.limits := by
  obtain ⟨draft, named, within⟩ := CatalogTable.draft_of_built built
  have layouts := table.withStrictKeys_layouts
  obtain ⟨shaped, ordinary, alias⟩ := CatalogTable.withStrictKeys_shaped draft
  refine Valid.createTable valid execution fresh notReserved shaped (fun _ => ordinary.trans draft.ordinary)
    ((names_eq_of_layout layouts).trans named)
    (by have := congrArg List.length layouts; simp only [List.length_map] at this; omega) notGenerated
    (by simpa using ordinaryNames) checked generated

/-- For every context in execution mode, valid catalog and successful resolution of CREATE TABLE, the
catalog after the resolution is valid. Proof sketch: split every branch of the resolver; a prepare error
returns the catalog, and the branch that appends a table is the one of
{name}`Catalog.Valid.createTable_withoutRowid` and {name}`Catalog.Valid.createTable_ordinary`. -/
theorem resolveCreateTable_valid (context : ResolveContext) (catalog after : Catalog)
    (name : Identifier) (columns : List Syntax.ColumnDefinition) (constraints : List Syntax.TableConstraint)
    (options : Syntax.TableOptions) (statement : Resolved.Statement)
    (valid : catalog.Valid context.profile.limits) (execution : context.mode = .execution)
    (ok : resolveCreateTable context catalog name columns constraints options = .ok (statement, after)) :
    after.Valid context.profile.limits := by
  unfold resolveCreateTable at ok
  simp only [issueResolution, prepareError, restrict] at ok
  repeat' split at ok
  all_goals first
    | (cases ok; exact valid)
    | (exact absurd (Catalog.find_not_trigger _ _ _ _ (by assumption)) (by simp [CatalogObject.isTrigger,
        CatalogEntry.isTrigger]))
    | (cases ok; done)
    | (cases ok; exact Catalog.Valid.createTable_withoutRowid valid execution (by assumption) (by assumption)
        (by assumption) (by assumption) (by assumption) (by assumption) (by assumption))
    | (cases ok; exact Catalog.Valid.createTable_ordinary valid execution (by assumption) (by assumption)
        (by assumption) (by assumption) (by assumption) (by assumption) (by assumption))

end Belay.Sqlite.Model
