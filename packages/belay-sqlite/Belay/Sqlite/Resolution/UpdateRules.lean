import Belay.Sqlite.Resolution.PrepareSpec
import Belay.Sqlite.Resolution.OperandIssues

set_option doc.verso true

/-! The prepare-error rule for UPDATE. See {lit}`Belay.Sqlite.Resolution.PrepareSpec` for
the rule and its references. -/

namespace Belay.Sqlite

/-- For every setting, scope, key columns, item and assignment, the issues of
{name}`resolveAssignment` name no catalog object. Proof sketch: the expression's issues
are issues of {name}`resolveOperand`; the column lookup fails only with
{name}`PrepareError.noSuchColumn`, and the key and constant checks only with a
restriction. -/
theorem resolveAssignment_issues (dqs : Bool) (scope : Scope) (keyColumns : List Nat)
    (item : Nat) (assignment : String × Syntax.Expr) :
    IssuesNameNoObject (resolveAssignment dqs scope keyColumns item assignment) := by
  obtain ⟨name, value⟩ := assignment
  unfold resolveAssignment
  apply bind_issues (under_issues _ (resolveOperand_issue _ _ _ _))
  intro operand
  apply bind_issues
  · intro issue failed
    split at failed <;> cases failed
    simp [ValueIssue.namesNoObject, PrepareError.namesObject]
  · intro position issue failed
    split at failed
    · cases failed; trivial
    · split at failed <;> cases failed
      trivial

/-- For every setting, scope and optional filter, the issues of the filter of
UPDATE, resolved as a condition, name no catalog object. Proof sketch: by
{name}`condition_issues` over {name}`resolveOperand_issue`. -/
theorem updateFilter_issues (dqs : Bool) (scope : Scope) (filter : Option Syntax.Expr) :
    IssuesNameNoObject (match filter with
      | none => (.ok none : Except ValueIssue (Option Resolved.Expr))
      | some term => some <$> condition [] (resolveOperand dqs scope true term)) := by
  cases filter with
  | none => intro issue failed; cases failed
  | some term =>
    intro issue failed
    have issues := condition_issues [] (resolveOperand_issue dqs scope true term)
    cases h : condition [] (resolveOperand dqs scope true term) with
    | error cause => simp [h, Functor.map, Except.map] at failed; subst failed; exact issues _ h
    | ok _ => simp [h, Functor.map, Except.map] at failed

/-- For every UPDATE whose resolution is a prepare error that names a catalog object:
the error is {lit}`no such table` for the statement's table, no table has the folded
name, and the catalog is unchanged. Proof sketch: split every branch of the
resolver; after the table lookup, the assignments, the filter and the
{lit}`RETURNING` columns give errors that name no catalog object. -/
theorem resolveUpdate_named (context : ResolveContext) (catalog after : Catalog) (index : Nat)
    (tableName : String) (assignments : List (String × Syntax.Expr)) (filter : Option Syntax.Expr)
    (returning : List Syntax.ResultColumn)
    (error : PrepareError) (named : error.namesObject = true)
    (ok : resolveUpdate context catalog index tableName assignments filter returning = .ok (.prepareError error, after)) :
    error = .noSuchTable tableName ∧ catalog.findTable tableName = none ∧ after = catalog := by
  unfold resolveUpdate at ok
  simp only [prepareError, restrict, issueResolution] at ok
  repeat' split at ok
  all_goals (try (cases ok; done))
  all_goals cases ok
  all_goals first
    | (simp_all; done)
    | (rename_i _ _ cause; have := resolveAll_issue _ _ _ (fun _ _ _ h => resolveAssignment_issues _ _ _ _ _ _ h) cause
       simp_all [ValueIssue.namesNoObject]; done)
    | (rename_i _ _ _ cause; have := updateFilter_issues _ _ _ _ cause
       simp_all [ValueIssue.namesNoObject]; done)
    | (rename_i _ _ cause; have := resolveReturning_issue _ _ _ _ cause
       simp_all [ValueIssue.namesNoObject]; done)

/-- For every UPDATE: when no table has the folded name, the resolution is
{lit}`no such table`, and the catalog is unchanged. -/
theorem resolveUpdate_missing (context : ResolveContext) (catalog : Catalog) (index : Nat)
    (tableName : String) (assignments : List (String × Syntax.Expr)) (filter : Option Syntax.Expr)
    (returning : List Syntax.ResultColumn)
    (missing : catalog.findTable tableName = none) :
    resolveUpdate context catalog index tableName assignments filter returning =
      .ok (.prepareError (.noSuchTable tableName), catalog) := by
  unfold resolveUpdate
  simp [missing, prepareError]

end Belay.Sqlite
