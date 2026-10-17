import Belay.Sqlite.Resolution.ReadDefaults
import Belay.Sqlite.StoreValueLaws

set_option doc.verso true

/-! Laws of the defaults that old rows read after ADD COLUMN ({lit}`ReadDefaults.lean`): the
value that {lit}`readDefaultValue` gives is already stored with the column's affinity. They
are kept apart from the definitions, as {lit}`StoreValueLaws.lean` is from
{lit}`StoreValue.lean`, so that execution does not import the laws of {lit}`storeValue`. -/

namespace Belay.Sqlite

/-- For every affinity, token and negation flag, storing the result of
{name}`readNumericDefault` again leaves it unchanged. The proof uses the
idempotence of {name}`storeValue`; no valid-token assumption is needed. -/
theorem readNumericDefault_stored (affinity : Affinity) (token : String) (negated : Bool) :
    storeValue affinity (readNumericDefault affinity token negated) = readNumericDefault affinity token negated := by
  unfold readNumericDefault
  exact storeValue_storeValue _ _

/-- For every column and value, if {name}`readDefaultValue` returns that value,
storing it with the column's affinity leaves it unchanged. An error return
satisfies no premise. The proof separates absent and numeric defaults from
other evaluated literals, then uses {name}`storeValue_storeValue`. -/
theorem readDefaultValue_stored (column : CatalogColumn) (value : Value)
    (accepted : readDefaultValue column = .ok value) : storeValue column.affinity value = value := by
  have mapped (result : Except ValueIssue Value)
      (returned : result.map (storeValue column.affinity) = .ok value) :
      storeValue column.affinity value = value := by
    cases result with
    | error issue => cases returned
    | ok input => cases returned; exact storeValue_storeValue _ _
  unfold readDefaultValue at accepted
  split at accepted
  · cases accepted; exact storeValue_null _
  · split at accepted
    all_goals first
      | (cases accepted; exact readNumericDefault_stored _ _ _)
      | exact mapped _ accepted

end Belay.Sqlite
