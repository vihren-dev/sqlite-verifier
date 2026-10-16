import Belay.Sqlite.Resolution.ErrorKinds

set_option doc.verso true

/-! The prepare-error rule ({lit}`lang_createtable.html` R-01232-54838 and the
{lit}`no such table` errors of {lit}`sqlite3LocateTable`): resolution gives a prepare
error that names a catalog object exactly when the named object is missing or the
name is already used. For each statement, one theorem shows that such an error has
its cause, and one shows that the cause gives the error. -/

namespace Belay.Sqlite

/-- For every column list and key, an error of {name}`keyPositions` names no catalog
object. Proof sketch: induction on the key; the only error is
{name}`PrepareError.noSuchColumn`. -/
theorem keyPositions_error (columns : List CatalogColumn) (names : List String) (error : PrepareError)
    (failed : keyPositions columns names = .error error) : error.namesObject = false := by
  induction names with
  | nil => cases failed
  | cons name rest ih =>
    simp only [keyPositions] at failed
    split at failed
    · cases h : keyPositions columns rest <;> simp_all [Except.map]
    · cases failed; rfl

/-- For all algorithms, an error of {name}`mergeAlgorithm` names no catalog object. Proof
sketch: the only error is {name}`PrepareError.conflictingAlgorithms`. -/
theorem mergeAlgorithm_error (first second : Option ConflictAlgorithm) (error : PrepareError)
    (failed : mergeAlgorithm first second = .error error) : error.namesObject = false := by
  unfold mergeAlgorithm at failed
  split at failed <;> (try split at failed) <;> cases failed <;> rfl

/-- For every table, key and algorithm, an error of {name}`addUniqueKey` names no catalog
object. Proof sketch: every error is an error of {name}`mergeAlgorithm_error`. -/
theorem addUniqueKey_error (table : CatalogTable) (positions : List Nat) (algorithm : Option ConflictAlgorithm)
    (error : PrepareError) (failed : addUniqueKey table positions algorithm = .error error) :
    error.namesObject = false := by
  unfold addUniqueKey at failed
  repeat' split at failed
  all_goals try simp only [bind, Except.bind] at failed
  all_goals (repeat' split at failed)
  all_goals first | (cases failed; done) | (cases failed <;> exact mergeAlgorithm_error _ _ _ (by assumption))

/-- For every table, key, alias, direction and algorithm, an error of
{name}`setPrimaryKey` names no catalog object. Proof sketch: every error is an error of
{name}`mergeAlgorithm_error`. -/
theorem setPrimaryKey_error (table : CatalogTable) (positions : List Nat) (alias : Option Nat) (descending : Bool)
    (algorithm : Option ConflictAlgorithm) (error : PrepareError)
    (failed : setPrimaryKey table positions alias descending algorithm = .error error) :
    error.namesObject = false := by
  unfold setPrimaryKey at failed
  repeat' split at failed
  all_goals try simp only [bind, Except.bind] at failed
  all_goals (repeat' split at failed)
  all_goals first | (cases failed; done) | (cases failed <;> exact mergeAlgorithm_error _ _ _ (by assumption))

/-- For every table and constraint, an error of {name}`applyConstraint` names no
catalog object. Proof sketch: the errors are {name}`PrepareError.multiplePrimaryKeys`,
{name}`PrepareError.defaultNotConstant`, and the errors of {name}`setPrimaryKey_error` and
{name}`addUniqueKey_error`. -/
theorem applyConstraint_error (tableName : String) (definition : Syntax.ColumnDefinition)
    (table : CatalogTable) (constraint : Syntax.ColumnConstraint) (error : PrepareError)
    (failed : applyConstraint tableName definition table constraint = .error error) :
    error.namesObject = false := by
  cases constraint <;> simp only [applyConstraint] at failed <;> (try split at failed)
  all_goals first
    | (cases failed <;> rfl)
    | exact setPrimaryKey_error _ _ _ _ _ _ failed
    | exact addUniqueKey_error _ _ _ _ failed

/-- If every step's error names no catalog object, so does an error of a fold of the
steps. Proof sketch: induction on the list; the error comes from the first step or
from the fold of the rest. -/
theorem foldlM_error (step : CatalogTable → Syntax.ColumnConstraint → Except PrepareError CatalogTable)
    (each : ∀ table constraint error, step table constraint = .error error → error.namesObject = false)
    (items : List Syntax.ColumnConstraint) (table : CatalogTable) (error : PrepareError)
    (failed : items.foldlM step table = .error error) : error.namesObject = false := by
  induction items generalizing table with
  | nil => cases failed
  | cons item rest ih =>
    simp only [List.foldlM, bind, Except.bind] at failed
    split at failed
    · cases failed; exact each _ _ _ (by assumption)
    · exact ih _ failed

/-- For all inputs, an error of {name}`addDefinitions` names no catalog object. Proof
sketch: induction on the definitions; the direct errors are the column limit and the
duplicate name, and constraint errors come from {name}`foldlM_error`. -/
theorem addDefinitions_error (limit : Nat) (tableName : String) (table : CatalogTable)
    (definitions : List Syntax.ColumnDefinition) (error : PrepareError)
    (failed : addDefinitions limit tableName table definitions = .error error) : error.namesObject = false := by
  induction definitions generalizing table with
  | nil => cases failed
  | cons definition rest ih =>
    simp only [addDefinitions, bind, Except.bind] at failed
    split at failed
    · cases failed; rfl
    · split at failed
      · cases failed; rfl
      · split at failed
        · rename_i _ cause; cases failed; exact foldlM_error _ (applyConstraint_error _ _) _ _ _ cause
        · exact ih _ failed

/-- For all inputs, an error of {name}`addTableConstraints` names no catalog object.
Proof sketch: induction on the constraints; the errors are a second primary key, the
key column errors of {name}`keyPositions_error`, and the merged keys of
{name}`setPrimaryKey_error` and {name}`addUniqueKey_error`. -/
theorem addTableConstraints_error (tableName : String) (table : CatalogTable)
    (constraints : List Syntax.TableConstraint) (error : PrepareError)
    (failed : addTableConstraints tableName table constraints = .error error) : error.namesObject = false := by
  induction constraints generalizing table with
  | nil => cases failed
  | cons constraint rest ih =>
    cases constraint with
    | primaryKey names algorithm =>
      simp only [addTableConstraints, bind, Except.bind] at failed
      split at failed
      · cases failed; rfl
      · split at failed
        · rename_i _ cause; cases failed; exact keyPositions_error _ _ _ cause
        · split at failed
          · rename_i _ cause; cases failed; exact setPrimaryKey_error _ _ _ _ _ _ cause
          · exact ih _ failed
    | unique names algorithm =>
      simp only [addTableConstraints, bind, Except.bind] at failed
      split at failed
      · rename_i _ cause; cases failed; exact keyPositions_error _ _ _ cause
      · split at failed
        · rename_i _ cause; cases failed; exact addUniqueKey_error _ _ _ _ cause
        · exact ih _ failed

end Belay.Sqlite
