import Belay.Sqlite.Resolution.Defaults
import Belay.Sqlite.StoreValueLaws

set_option doc.verso true

/-! Defaults for fields absent from old records after ADD COLUMN. SQLite uses
{lit}`sqlite3ValueFromExpr` here, which differs from expression evaluation for
INSERT. Affinity conversion still uses the shared {name}`Belay.Sqlite.storeValue`. -/

namespace Belay.Sqlite

/-- Read a numeric default using SQLite's literal-value path. Decimal text that
is not an in-range unsigned integer keeps its spelling under TEXT affinity.
An oversized hexadecimal token stays text, while unary minus converts that text
to zero. Negating the hexadecimal minimum integer produces a REAL value.
Separators are removed as the parser does. For example,
{lean}`readNumericDefault .text "1.50" false` reads the spelling {lit}`1.50`
for a TEXT column.
Use {name}`queryNumeric` for INSERT expression evaluation instead. -/
def readNumericDefault (affinity : Affinity) (token : String) (negated : Bool) : Value :=
  let text := String.ofList (token.toList.filter (· ≠ '_'))
  let value := match numericValue text false with
    | .integer integer =>
      if negated then
        if integer == -(2 ^ 63 : Int) then .real (9223372036854775808.0 : Float).toBits
        else .integer (-integer)
      else .integer integer
    | .hexTooBig => if negated then .integer 0 else .text text.toUTF8.toList
    | .real =>
      let bytes := ((if negated then "-" else "") ++ text).toUTF8.toList
      if affinity == .blob then
        if text.toList.any (fun c => c == '.' || c == 'e' || c == 'E') then realLiteral text.toList negated
        else numericText bytes
      else .text bytes
  storeValue affinity value

/-- Read a column's default for a field absent from an old record, applying its
column affinity. No default supplies NULL. Numeric tokens use
{name}`readNumericDefault`; other literal forms use {name}`writtenDefault`.
Time and compound expressions remain model restrictions. For omitted INSERT
values use {name}`defaultValue`, whose numeric errors have different semantics. -/
def readDefaultValue (column : CatalogColumn) : Except ValueIssue Value :=
  match column.defaultValue with
  | none => .ok .null
  | some written => match written.expression with
    | .numeric text | .positive (.numeric text) => .ok (readNumericDefault column.affinity text false)
    | .negate (.numeric text) => .ok (readNumericDefault column.affinity text true)
    | .null | .string _ | .blob _ | .currentTime _ | .identifier ..
    | .negate _ | .positive _ | .equals .. | .compare .. | .and .. | .or .. | .not _
    | .isNull .. | .callStar _ | .call .. | .arithmetic .. | .cast .. | .callPair .. | .qualified .. =>
      (writtenDefault written).map (storeValue column.affinity)

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
