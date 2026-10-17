import Belay.Sqlite.Resolution.ErrorKinds

set_option doc.verso true

/-! General lemmas about the issues of resolution: a computation whose issues name no
catalog object keeps that property through bind, a path prefix, a condition and a map.
The prepare-error rules of each statement use them. -/

namespace Belay.Sqlite

/-- Every issue of a computation names no catalog object. -/
abbrev IssuesNameNoObject (result : Except ValueIssue α) : Prop :=
  ∀ issue, result = .error issue → issue.namesNoObject

/-- For all computations: if the issues of the first and of every continuation name no
catalog object, so do the issues of their sequence. Proof sketch: a failed sequence
failed in the first computation, or in the continuation of its value. -/
theorem bind_issues {first : Except ValueIssue α} {next : α → Except ValueIssue β}
    (left : IssuesNameNoObject first) (right : ∀ value, IssuesNameNoObject (next value)) :
    IssuesNameNoObject (first >>= next) := by
  intro issue failed
  cases first with
  | error inner => cases failed; exact left _ rfl
  | ok value => exact right value issue failed

/-- For every computation and path: if its issues name no catalog object, so do its
issues under the path. Proof sketch: a path changes only the location of a
restriction ({name}`ValueIssue.under_namesNoObject`). -/
theorem under_issues {result : Except ValueIssue α} (path : List Nat) (issues : IssuesNameNoObject result) :
    IssuesNameNoObject (result.mapError (·.under path)) := by
  intro issue failed
  cases result with
  | error inner => cases failed; exact ValueIssue.under_namesNoObject _ _ (issues _ rfl)
  | ok _ => cases failed

/-- For every path and operand computation: if its issues name no catalog object, so
do the issues of {name}`condition`. Proof sketch: {name}`condition` passes an issue on
under the path, and adds only a restriction. -/
theorem condition_issues (path : List Nat) {result : Except ValueIssue Operand}
    (issues : IssuesNameNoObject result) : IssuesNameNoObject (condition path result) := by
  intro issue failed
  cases result with
  | error inner => cases failed; exact ValueIssue.under_namesNoObject _ _ (issues _ rfl)
  | ok operand => simp only [condition] at failed; split at failed <;> cases failed; trivial

/-- For every value computation and function: mapping the value keeps the issues.
Proof sketch: a failed map is the failed computation. -/
theorem map_issues {result : Except ValueIssue α} (function : α → β) (issues : IssuesNameNoObject result) :
    IssuesNameNoObject (result.map function) := by
  intro issue failed
  cases result with
  | error inner => cases failed; exact issues _ rfl
  | ok _ => cases failed

end Belay.Sqlite
