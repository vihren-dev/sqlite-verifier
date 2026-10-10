import Belay.Sqlite.Resolve

set_option doc.verso true

/-! Which prepare errors name a catalog object, and the lemmas that value conversion
and column handling never give such an error. The prepare-error rules use them to
show that only a missing or used object name gives these errors. -/

namespace Belay.Sqlite

/-- Whether the error says that a named catalog object is missing or that a name is
already used: {name}`PrepareError.noSuchTable`, {name}`PrepareError.tableExists`,
{name}`PrepareError.indexNameUsed`, {name}`PrepareError.tableNameUsed` or
{name}`PrepareError.indexExists`. -/
def PrepareError.namesObject : PrepareError → Bool
  | .noSuchTable _ | .tableExists _ | .indexNameUsed _ | .tableNameUsed _ | .indexExists _ => true
  | .reservedName _ | .tooManyColumns _ | .duplicateColumn _ | .multiplePrimaryKeys _
  | .defaultNotConstant _ | .noSuchColumn _ | .tableHasNoColumn .. | .valueCount ..
  | .valuesForColumns .. | .valuesDiffer | .tableMayNotBeAltered _ | .tableMayNotBeIndexed _
  | .cannotAddPrimaryKey | .cannotAddUnique | .hexLiteralTooBig _ => false

/-- A value issue that is not a prepare error naming a catalog object. -/
def ValueIssue.namesNoObject : ValueIssue → Prop
  | .prepare error => error.namesObject = false
  | .restriction .. => True

/-- For every expression, an issue of {name}`literalValue` names no catalog object.
Proof sketch: induction on the expression; the only prepare errors are
{name}`PrepareError.noSuchColumn` and {name}`PrepareError.hexLiteralTooBig`. -/
theorem literalValue_issue (dqs : Bool) (expression : Syntax.Expr) (issue : ValueIssue)
    (failed : literalValue dqs expression = .error issue) : issue.namesNoObject := by
  induction expression generalizing issue with
  | positive operand ih =>
    simp only [literalValue, Except.mapError] at failed
    split at failed <;> try contradiction
    rename_i inner hinner
    cases failed
    have := ih inner hinner
    split <;> simp_all [ValueIssue.namesNoObject]
  | numeric text =>
    simp only [literalValue, numericLiteral] at failed
    split at failed <;> cases failed <;> simp [ValueIssue.namesNoObject, PrepareError.namesObject]
  | negate operand =>
    cases operand <;> simp only [literalValue, numericLiteral] at failed <;>
      (try split at failed) <;> cases failed <;> simp [ValueIssue.namesNoObject, PrepareError.namesObject]
  | identifier name doubleQuoted =>
    simp only [literalValue] at failed
    split at failed <;> cases failed; simp [ValueIssue.namesNoObject, PrepareError.namesObject]
  | _ => simp only [literalValue] at failed <;> cases failed <;> simp [ValueIssue.namesNoObject]

/-- For every resolver, start and list: if {name}`resolveAllFrom` fails, some item
failed with the same issue. -/
theorem resolveAllFrom_error (resolveOne : Nat → α → Except ValueIssue β) (start : Nat)
    (items : List α) (issue : ValueIssue) (failed : resolveAllFrom resolveOne start items = .error issue) :
    ∃ position item, resolveOne position item = .error issue := by
  induction items generalizing start with
  | nil => cases failed
  | cons item rest ih =>
    simp only [resolveAllFrom, bind, Except.bind] at failed
    split at failed
    · cases failed; exact ⟨_, _, by assumption⟩
    · split at failed
      · cases failed; exact ih _ (by assumption)
      · cases failed

/-- If every item's issue names no catalog object, so does an issue of
{name}`resolveAll`. -/
theorem resolveAll_issue (resolveOne : Nat → α → Except ValueIssue β) (items : List α) (issue : ValueIssue)
    (each : ∀ position item issue, resolveOne position item = .error issue → issue.namesNoObject)
    (failed : resolveAll resolveOne items = .error issue) : issue.namesNoObject := by
  obtain ⟨_, _, h⟩ := resolveAllFrom_error _ _ _ _ failed
  exact each _ _ _ h

/-- An issue with a prefixed path names an object exactly when the issue does. -/
theorem ValueIssue.under_namesNoObject (prefix_ : List Nat) (issue : ValueIssue)
    (named : issue.namesNoObject) : (issue.under prefix_).namesNoObject := by
  cases issue <;> simp_all [ValueIssue.under, ValueIssue.namesNoObject]

/-- For every column, an issue of {name}`defaultValue` names no catalog object. -/
theorem defaultValue_issue (dqs : Bool) (column : CatalogColumn) (issue : ValueIssue)
    (failed : defaultValue dqs column = .error issue) : issue.namesNoObject := by
  unfold defaultValue at failed
  split at failed
  · cases failed
  · cases failed
  · exact literalValue_issue _ _ _ failed

/-- For every column list, an issue of {name}`assignedValue` names no catalog object. -/
theorem assignedValue_issue (columns : List CatalogColumn) (dqs : Bool) (expression : Syntax.Expr)
    (issue : ValueIssue) (failed : assignedValue columns dqs expression = .error issue) :
    issue.namesNoObject := by
  unfold assignedValue at failed
  split at failed
  · split at failed
    · cases failed; trivial
    · exact literalValue_issue _ _ _ failed
  · exact literalValue_issue _ _ _ failed

/-- For every affinity, value and path, an issue of {name}`storedValue` is a model restriction. -/
theorem storedValue_issue (affinity : Affinity) (value : Value) (path : List Nat) (issue : ValueIssue)
    (failed : storedValue affinity value path = .error issue) : issue.namesNoObject := by
  unfold storedValue at failed
  split at failed <;> cases failed; trivial

/-- For all inputs, an issue of {name}`fullRow` names no catalog object. -/
theorem fullRow_issue (dqs : Bool) (columns : List CatalogColumn) (positions : List Nat) (row : List Value)
    (issue : ValueIssue) (failed : fullRow dqs columns positions row = .error issue) : issue.namesNoObject := by
  unfold fullRow at failed
  refine resolveAll_issue _ _ _ (fun position column issue h => ?_) failed
  simp only [bind, Except.bind] at h
  split at h
  · exact storedValue_issue _ _ _ _ h
  · split at h
    · cases h; exact defaultValue_issue _ _ _ (by assumption)
    · exact storedValue_issue _ _ _ _ h

end Belay.Sqlite
