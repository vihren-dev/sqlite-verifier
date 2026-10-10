import Belay.Sqlite.ResolvePrepareSpec

set_option doc.verso true

/-! The prepare-error rule for each statement. See the module
{lit}`Belay.Sqlite.ResolvePrepareSpec` for the rule and its references. -/

namespace Belay.Sqlite

/-- For every column limit, name, columns and constraints, an error of the table
definition steps of CREATE TABLE names no catalog object. Proof sketch: the error
comes from {name}`addDefinitions_error` or from {name}`addTableConstraints_error`. -/
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

/-- For every setting and VALUES rows, an issue of the INSERT value conversion names no
catalog object. Proof sketch: each row's issue is an issue of {name}`literalValue`
with a prefixed path, by {name}`resolveAll_issue` twice. -/
theorem insertValues_issue (dqs : Bool) (rows : List (List Syntax.Expr)) (issue : ValueIssue)
    (failed : resolveAll (fun row values => (resolveAll (fun _ => literalValue dqs) values).mapError
      (·.under [row])) rows = .error issue) : issue.namesNoObject := by
  refine resolveAll_issue _ _ _ (fun row values inner h => ?_) failed
  simp only [Except.mapError] at h
  split at h <;> cases h
  exact ValueIssue.under_namesNoObject _ _
    (resolveAll_issue _ _ _ (fun _ _ _ h => literalValue_issue _ _ _ h) (by assumption))

/-- For every column list and names, an error of {name}`insertPositions` names no
catalog object. Proof sketch: induction on the names; the only error is
{name}`PrepareError.tableHasNoColumn`. -/
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
name, and the catalog is unchanged. Proof sketch: split every branch of the
resolver; the branches after the table lookup give errors that name no catalog
object, by the lemmas on column lists, values and full rows. -/
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

end Belay.Sqlite
