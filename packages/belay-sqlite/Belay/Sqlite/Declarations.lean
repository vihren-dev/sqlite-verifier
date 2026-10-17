set_option doc.verso true

/-! Stored values, rows, column affinities and SQLite's identifier folding. The
catalog, the resolved statements and the execution semantics share them. -/

namespace Belay.Sqlite

/-- SQLite column affinities. {lean}`Affinity.integer` describes INTEGER affinity;
the catalog computes each column's affinity from its declared type text. -/
inductive Affinity where
  /-- INTEGER affinity, for example an INTEGER or BIGINT declaration. -/
  | integer
  /-- REAL affinity, for example a REAL declaration. -/
  | real
  /-- TEXT affinity, for example a TEXT or VARCHAR declaration. -/
  | text
  /-- BLOB affinity, including a column with no declared type. -/
  | blob
  /-- NUMERIC affinity, for example a NUMERIC or TIMESTAMP declaration. -/
  | numeric
  deriving Repr, DecidableEq

/-- Opaque stored values; preservation neither evaluates nor coerces them.
Use {lean}`Value.null` for NULL. Not every tagged value is representable by SQLite. -/
inductive Value where
  /-- A NULL cell, distinct from an empty text or BLOB cell. -/
  | null
  /-- An integer cell; native representability requires a separate range check. -/
  | integer (value : Int)
  /-- A REAL cell's exact IEEE bits, preserving distinctions such as signed zero. -/
  | real (bits : UInt64)
  /-- A text cell's bytes; no encoding conversion is performed here. -/
  | text (bytes : List UInt8)
  /-- A BLOB cell's bytes; {lean}`Value.blob []` is an empty BLOB. -/
  | blob (bytes : List UInt8)
  deriving Repr, DecidableEq

/-- A stored row with physical identity and ordered cells. Supply the SQLite
rowid rather than an application key; use an empty cell list only for zero width. -/
structure Row where
  /-- Physical rowid; the admitted signed 64-bit range is checked separately. -/
  rowid : Int
  /-- Cells in column order; the list retains NULLs and duplicate values. -/
  values : List Value
  deriving Repr, DecidableEq

/-- Copy SQLite's ASCII-only case folding, including decoded quoted identifiers.
Fold ASCII capitals to lowercase and leave every other character unchanged; for
example, {lit}`Ab_É` folds to {lit}`ab_É`. The fold goes through the character list:
in the kernel proofs of conformance cases, {lit}`String.map` takes seconds for each
name that has a capital, and the list takes milliseconds. -/
def normalizeIdentifier (name : String) : String :=
  String.ofList (name.toList.map fun c => if 'A' ≤ c ∧ c ≤ 'Z' then Char.ofNat (c.toNat + 32) else c)

/-- Whether a name is SQLite's TRUE or FALSE keyword, ignoring ASCII letter case.
Recognize boolean literals without treating ordinary column names as constants.
For example, {lean}`booleanKeywordName "TrUe"` is true. This predicate checks only
spelling; callers check the expression's quote flag. -/
def booleanKeywordName (name : String) : Bool :=
  ["true", "false"].contains (normalizeIdentifier name)

end Belay.Sqlite
