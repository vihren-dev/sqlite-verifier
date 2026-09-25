import SqliteVerifier.SqlExecution

/-! Kernel-checked finite SQL regressions complement independent native comparisons.
They exercise ordinary table names and values, not application-specific policy. -/
namespace SqliteVerifier.SqlExamples

/-- BIGINT PRIMARY KEY remains an ordinary nullable column, distinct from rowid. -/
def columns : List Column := [
  { name := "key", affinity := .integer, declaredType := .bigInt },
  { name := "value", affinity := .text, notNull := true }]

/-- Negative physical identities and a NULL key exercise both distinct semantics. -/
def original : Table where
  columns := columns
  properties := { primaryKey := ["key"] }
  rows := [⟨-5, [.null, .text [97]]⟩, ⟨-2, [.integer 1, .text [98]]⟩]

/-- Only the declared ordinary table exists in this finite starting state. -/
def database : Database := fun name => if name = "records" then some original else none

/-- A nullable added field preserves old observations through a transactional DML script. -/
def note : Column := { name := "note", affinity := .text }

/-- The file itself supplies both transaction control and literal writes. -/
def script : List Statement := [.beginTransaction, .addColumn "records" note,
  .insert "records" ["key", "value", "note"] [.integer 2, .text [99], .null],
  .commit, .update "records" "value" (.text [100]) "key" 2]

/-- Observe transaction status without comparing function-valued databases. -/
def openTransaction : Outcome → Bool
  | .pending .. => true
  | _ => false

/-- Native-style statement failures retain their location and constraint category. -/
def error : Outcome → Option (Nat × ExecutionError)
  | .failure position reason _ => some (position, reason)
  | .pending _ _ reason => reason
  | .success _ => none

example : LiteralData.nextRowid original.rows = -1 := by decide +kernel
example : supportedSqlFrom 0 script { database := database } = true := by decide +kernel
example : error (runSql script database) = none ∧ openTransaction (runSql script database) = false := by
  decide +kernel
example : ((runSql script database).database "records").map Table.rows = some [
    ⟨-5, [.null, .text [97], .null]⟩, ⟨-2, [.integer 1, .text [98], .null]⟩,
    ⟨-1, [.integer 2, .text [100], .null]⟩] := by decide +kernel

/-- The unique-key failure stops after ADD, while BEGIN remains open. -/
def rejected : List Statement := [.beginTransaction, .addColumn "records" note,
  .insert "records" ["key", "value", "note"] [.integer 1, .text [], .null], .rollback]

example : error (runSql rejected database) = some (2, .constraintViolation) ∧
    openTransaction (runSql rejected database) = true := by decide +kernel
example : ((runSql rejected database).database "records").map Table.columns = some (columns ++ [note]) ∧
    ((runSql rejected database).persistedDatabase "records").map Table.columns = some columns := by
  decide +kernel
example : ((runSql [.beginTransaction, .insert "records" ["key", "value"]
    [.integer 2, .text []], .rollback] database).database "records") = some original := by decide +kernel
example : error (runSql [.commit] database) = some (0, .noActiveTransaction) := by decide +kernel
example : error (runSql [.beginTransaction, .beginTransaction] database) =
    some (1, .transactionAlreadyActive) := by decide +kernel
example : openTransaction (runSql [.beginTransaction] database) = true := by decide +kernel
example : error (runSql [.insert "records" ["key", "value"] [.integer 2, .null]] database) =
    some (0, .constraintViolation) := by decide +kernel

-- Unsupported coercions and random rowid allocation are failed domain obligations,
-- not modeled native constraint errors. Nullable duplicate keys remain supported.
example : LiteralData.lossless { name := "x", affinity := .text } (.integer 7) = false := by decide +kernel
example : LiteralData.lossless { name := "x", affinity := .numeric } (.text [49, 50]) = false := by decide +kernel
example : LiteralData.lossless { name := "x", affinity := .numeric }
    (.text "2026-09-25 00:00:00".toUTF8.toList) = true := by decide +kernel
example : LiteralData.insertReady { original with rows := [⟨9223372036854775807, [.null, .text []]⟩] }
    ["key", "value"] [.integer 2, .text []] = false := by decide +kernel
example : LiteralData.constraints (LiteralData.inserted original [.null, .text []]) = true := by decide +kernel
example : script.all Statement.isExtension = false := by decide +kernel

end SqliteVerifier.SqlExamples
