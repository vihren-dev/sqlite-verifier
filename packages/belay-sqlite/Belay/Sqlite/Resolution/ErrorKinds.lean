import Belay.Sqlite.Resolution.Resolve

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
  | .cannotAddPrimaryKey | .cannotAddUnique | .hexLiteralTooBig _ | .misuseOfAggregate _
  | .aggregateInGroupBy | .orderByOutOfRange .. | .groupByOutOfRange .. | .wrongArgumentCount _
  | .ambiguousColumn _ | .noSuchSource _ | .tooManyTables | .returningSourceStar
  | .joinUsingColumn _ | .naturalJoinCondition | .ambiguousUsingReference _ | .conflictTargetMismatch
  | .conflictingAlgorithms => false

/-- A value issue that is not a prepare error naming a catalog object. -/
def ValueIssue.namesNoObject : ValueIssue → Prop
  | .prepare error => error.namesObject = false
  | .restriction .. => True

/-- For every resolver, start and list: if {name}`resolveAllFrom` fails with an
issue, there is a position and an item for which the resolver fails with the same
issue. The formula does not say that the item is in the list or where. Proof sketch:
induction on the list; the failure comes from the head or from the tail. -/
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

/-- If every call of the resolver fails only with issues that name no catalog object,
an issue of {name}`resolveAll` names no catalog object. Proof sketch: by
{name}`resolveAllFrom_error`, the issue is the issue of one call. -/
theorem resolveAll_issue (resolveOne : Nat → α → Except ValueIssue β) (items : List α) (issue : ValueIssue)
    (each : ∀ position item issue, resolveOne position item = .error issue → issue.namesNoObject)
    (failed : resolveAll resolveOne items = .error issue) : issue.namesNoObject := by
  obtain ⟨_, _, h⟩ := resolveAllFrom_error _ _ _ _ failed
  exact each _ _ _ h

/-- For every prefix and issue: if the issue names no catalog object, the issue with
the prefixed path names no catalog object. This is one direction only. Proof sketch:
a prefix changes only the path of a restriction. -/
theorem ValueIssue.under_namesNoObject (prefix_ : List Nat) (issue : ValueIssue)
    (named : issue.namesNoObject) : (issue.under prefix_).namesNoObject := by
  cases issue <;> simp_all [ValueIssue.under, ValueIssue.namesNoObject]

/-- For every column, an issue of {name}`defaultValue` names no catalog object.
Proof sketch: the function fails only with model restrictions. -/
theorem defaultValue_issue (column : CatalogColumn) (issue : ValueIssue)
    (failed : defaultValue column = .error issue) : issue.namesNoObject := by
  unfold defaultValue at failed
  split at failed <;> cases failed <;> trivial

/-- For all inputs, an issue of {name}`fullRow` names no catalog object. Proof sketch:
by {name}`resolveAll_issue`, the issue comes from one column, where only
{name}`defaultValue` can fail. -/
theorem fullRow_issue (columns : List CatalogColumn) (positions : List Nat) (row : List Value)
    (issue : ValueIssue) (failed : fullRow columns positions row = .error issue) : issue.namesNoObject := by
  unfold fullRow at failed
  refine resolveAll_issue _ _ _ (fun position column issue h => ?_) failed
  simp only [bind, Except.bind] at h
  split at h
  · cases h
  · cases hdefault : defaultValue column with
    | error cause => rw [hdefault] at h; cases h; exact defaultValue_issue _ _ hdefault
    | ok _ => rw [hdefault] at h; cases h

end Belay.Sqlite
