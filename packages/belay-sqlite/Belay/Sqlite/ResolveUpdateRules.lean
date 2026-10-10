import Belay.Sqlite.ResolvePrepareSpec

set_option doc.verso true

/-! The prepare-error rule for UPDATE. See {lit}`Belay.Sqlite.ResolvePrepareSpec` for
the rule and its references. -/

namespace Belay.Sqlite

/-- For every context, column list and filter, an issue of the WHERE filter of UPDATE
names no catalog object. Proof sketch: split every branch; the errors are
{name}`PrepareError.noSuchColumn`, restrictions, and issues of
{name}`assignedValue_issue`. -/
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

/-- For every column list and assignments, an error of the SET column lookup names no
catalog object. Proof sketch: induction on the assignments; the only error is
{name}`PrepareError.noSuchColumn`. -/
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
name, and the catalog is unchanged. Proof sketch: split every branch of the
resolver; after the table lookup, the SET values, the SET columns, the filter and the
stored values give errors that name no catalog object. -/
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
