import Belay.Sqlite.ResolvePrepareSpec

set_option doc.verso true

/-! The prepare-error rule for each statement. See the module
{lit}`Belay.Sqlite.ResolvePrepareSpec` for the rule and its references. -/

namespace Belay.Sqlite

/-- An error of the table definition steps of CREATE TABLE names no catalog object. -/
theorem tableDefinition_error (limit : Nat) (name : String) (columns : List Syntax.ColumnDefinition)
    (constraints : List Syntax.TableConstraint) (error : PrepareError)
    (failed : (addDefinitions limit name { columns := [] } columns >>= (addTableConstraints name · constraints))
      = .error error) : error.namesObject = false := by
  simp only [bind, Except.bind] at failed
  split at failed
  · rename_i _ cause; cases failed; exact addDefinitions_error _ _ _ _ _ cause
  · exact addTableConstraints_error _ _ _ _ failed

/-- For every CREATE TABLE whose resolution is a prepare error that names a catalog
object, the catalog has an object with the folded name, and the catalog is unchanged. -/
theorem resolveCreateTable_named (context : ResolveContext) (catalog after : Catalog) (index : Nat)
    (name : String) (columns : List Syntax.ColumnDefinition) (constraints : List Syntax.TableConstraint)
    (error : PrepareError) (named : error.namesObject = true)
    (ok : resolveCreateTable context catalog index name columns constraints = .ok (.prepareError error, after)) :
    (catalog.find name).isSome = true ∧ after = catalog := by
  unfold resolveCreateTable at ok
  simp only [prepareError, restrict] at ok
  repeat' split at ok
  all_goals (try (cases ok; done))
  all_goals cases ok
  all_goals first
    | (simp [PrepareError.namesObject] at named; done)
    | (rename_i cause; simp [tableDefinition_error _ _ _ _ _ cause] at named; done)
    | (simp_all; done)

/-- For every CREATE TABLE of a name that SQLite does not reserve: when the catalog
has an object with the folded name, the resolution is a prepare error that names a
catalog object, and the catalog is unchanged. -/
theorem resolveCreateTable_used (context : ResolveContext) (catalog : Catalog) (index : Nat)
    (name : String) (columns : List Syntax.ColumnDefinition) (constraints : List Syntax.TableConstraint)
    (notReserved : reservedName name = false) (used : (catalog.find name).isSome = true) :
    ∃ error, error.namesObject = true ∧
      resolveCreateTable context catalog index name columns constraints = .ok (.prepareError error, catalog) := by
  unfold resolveCreateTable
  simp only [notReserved, Bool.false_and, Bool.false_eq_true, ite_false, prepareError]
  cases found : catalog.find name with
  | none => simp [found] at used
  | some result =>
    obtain ⟨_, object⟩ := result
    cases entry : object.entry <;> cases object <;> simp_all [PrepareError.namesObject]

/-- An issue of the VALUES rows of INSERT names no catalog object. -/
theorem insertValues_issue (dqs : Bool) (rows : List (List Syntax.Expr)) (issue : ValueIssue)
    (failed : resolveAll (fun row values => (resolveAll (fun _ => literalValue dqs) values).mapError
      (·.under [row])) rows = .error issue) : issue.namesNoObject := by
  refine resolveAll_issue _ _ _ (fun row values inner h => ?_) failed
  simp only [Except.mapError] at h
  split at h <;> cases h
  exact ValueIssue.under_namesNoObject _ _
    (resolveAll_issue _ _ _ (fun _ _ _ h => literalValue_issue _ _ _ h) (by assumption))

/-- For every column list and names, an error of {name}`insertPositions` names no catalog object. -/
theorem insertPositions_error (tableName : String) (columns : List CatalogColumn) (names : List String)
    (error : PrepareError) (failed : insertPositions tableName columns names = .error error) :
    error.namesObject = false := by
  induction names with
  | nil => cases failed
  | cons name rest ih =>
    simp only [insertPositions] at failed
    split at failed
    · cases h : insertPositions tableName columns rest <;> simp_all [Except.map]
    · cases failed; rfl

/-- For every INSERT whose resolution is a prepare error that names a catalog object:
the error is {lit}`no such table` for the statement's table, no table has the folded
name, and the catalog is unchanged. -/
theorem resolveInsert_named (context : ResolveContext) (catalog after : Catalog) (index : Nat)
    (tableName : String) (names : Option (List String)) (rows : List (List Syntax.Expr))
    (error : PrepareError) (named : error.namesObject = true)
    (ok : resolveInsert context catalog index tableName names rows = .ok (.prepareError error, after)) :
    error = .noSuchTable tableName ∧ catalog.findTable tableName = none ∧ after = catalog := by
  unfold resolveInsert at ok
  simp only [prepareError, restrict, issueResolution] at ok
  repeat' split at ok
  all_goals (try (cases ok; done))
  all_goals cases ok
  all_goals first
    | (simp [PrepareError.namesObject] at named; done)
    | (simp_all; done)
    | (rename_i cause; simp [insertPositions_error _ _ _ _ cause] at named; done)
    | (rename_i _ _ cause; have := insertValues_issue _ _ _ cause
       simp_all [ValueIssue.namesNoObject]; done)
    | (rename_i _ _ cause; have := resolveAll_issue _ _ _
         (fun _ row _ h => fullRow_issue _ _ _ row _ h) cause
       simp_all [ValueIssue.namesNoObject]; done)
    | (rename_i cause; cases names <;> simp only at cause <;>
        first | cases cause | simp [insertPositions_error _ _ _ _ cause] at named)

/-- For every INSERT whose VALUES rows all have the width of the first row: when no
table has the folded name, the resolution is {lit}`no such table`, and the catalog
is unchanged. -/
theorem resolveInsert_missing (context : ResolveContext) (catalog : Catalog) (index : Nat)
    (tableName : String) (names : Option (List String)) (rows : List (List Syntax.Expr))
    (same : ∀ row ∈ rows, row.length = (rows.head?.map List.length).getD 0)
    (missing : catalog.findTable tableName = none) :
    resolveInsert context catalog index tableName names rows = .ok (.prepareError (.noSuchTable tableName), catalog) := by
  have consistent : (rows.any fun row => row.length != (rows.head?.map List.length).getD 0) = false := by
    simpa using same
  unfold resolveInsert
  simp [consistent, missing, prepareError]

/-- An issue of the WHERE filter of UPDATE names no catalog object. -/
theorem resolveFilter_issue (context : ResolveContext) (columns : List CatalogColumn)
    (filter : Option Syntax.Expr) (issue : ValueIssue)
    (failed : resolveFilter context columns filter = .error issue) : issue.namesNoObject := by
  unfold resolveFilter at failed
  repeat' split at failed
  all_goals first
    | (cases failed; done)
    | (cases failed; simp [ValueIssue.namesNoObject, PrepareError.namesObject]; done)
    | (cases failed; trivial)
    | skip
  all_goals simp only [bind, Except.bind, Except.mapError] at failed
  all_goals (repeat' split at failed)
  all_goals first
    | (cases failed; done)
    | (cases failed; trivial)
    | (rename_i cause; split at cause
       · rename_i inner hinner
         cases cause; cases failed
         exact ValueIssue.under_namesNoObject _ _ (assignedValue_issue _ _ _ _ hinner)
       · cases cause)

/-- For every column list, an error of the SET column lookup names no catalog object. -/
theorem assignmentPositions_error (columns : List CatalogColumn) (assignments : List (String × Syntax.Expr))
    (error : PrepareError)
    (failed : assignments.mapM (fun (name, _) => (columnPosition columns name).elim
      (Except.error (PrepareError.noSuchColumn name)) Except.ok) = .error error) :
    error.namesObject = false := by
  induction assignments with
  | nil => cases failed
  | cons assignment rest ih =>
    simp only [List.mapM_cons, bind, Except.bind] at failed
    split at failed
    · rename_i _ cause
      cases failed
      cases h : columnPosition columns assignment.1 <;> simp_all [Option.elim]
      cases cause; rfl
    · split at failed
      · cases failed; exact ih (by assumption)
      · cases failed

/-- For every UPDATE whose resolution is a prepare error that names a catalog object:
the error is {lit}`no such table` for the statement's table, no table has the folded
name, and the catalog is unchanged. -/
theorem resolveUpdate_named (context : ResolveContext) (catalog after : Catalog) (index : Nat)
    (tableName : String) (assignments : List (String × Syntax.Expr)) (filter : Option Syntax.Expr)
    (error : PrepareError) (named : error.namesObject = true)
    (ok : resolveUpdate context catalog index tableName assignments filter = .ok (.prepareError error, after)) :
    error = .noSuchTable tableName ∧ catalog.findTable tableName = none ∧ after = catalog := by
  unfold resolveUpdate at ok
  simp only [prepareError, restrict, issueResolution] at ok
  repeat' split at ok
  all_goals (try (cases ok; done))
  all_goals cases ok
  all_goals first
    | (simp_all; done)
    | (rename_i cause; simp [assignmentPositions_error _ _ _ cause] at named; done)
    | (rename_i _ _ cause; have := resolveAll_issue _ _ _ (fun _ _ _ h => by
         simp only [Except.mapError] at h; split at h <;> cases h
         exact ValueIssue.under_namesNoObject _ _ (assignedValue_issue _ _ _ _ (by assumption))) cause
       simp_all [ValueIssue.namesNoObject]; done)
    | (rename_i _ _ cause; have := resolveFilter_issue _ _ _ _ cause
       simp_all [ValueIssue.namesNoObject]; done)
    | (rename_i _ _ cause; have := resolveAll_issue _ _ _ (fun _ _ _ h => storedValue_issue _ _ _ _ h) cause
       simp_all [ValueIssue.namesNoObject]; done)

/-- For every UPDATE: when no table has the folded name, the resolution is
{lit}`no such table`, and the catalog is unchanged. -/
theorem resolveUpdate_missing (context : ResolveContext) (catalog : Catalog) (index : Nat)
    (tableName : String) (assignments : List (String × Syntax.Expr)) (filter : Option Syntax.Expr)
    (missing : catalog.findTable tableName = none) :
    resolveUpdate context catalog index tableName assignments filter =
      .ok (.prepareError (.noSuchTable tableName), catalog) := by
  unfold resolveUpdate
  simp [missing, prepareError]

end Belay.Sqlite
