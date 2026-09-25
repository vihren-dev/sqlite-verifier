import HistoryDecoding

/-! Finite kernel-checked decoder boundaries complement the universal interpretation
proof. These are business observations, not a proof of Rust-library equivalence. -/
namespace HistoryDecodingChecks
open SqliteVerifier HistoryModel HistoryDecoding

/-- A canonical stored history with optional fields and non-UUID session text. -/
def cells : List (Option Value) := [
  some (.text "00000000000000000000000000000001".toUTF8.toList),
  some (.integer (-9223372036854775808)), some (.integer (-1)), some (.integer 0),
  some (.text "echo λ".toUTF8.toList), some (.text "/tmp".toUTF8.toList),
  some (.text "terminal one".toUTF8.toList), some (.text "host:user:extra".toUTF8.toList),
  some .null, some (.text "\u00A0\u2003".toUTF8.toList), some (.text "  reason  ".toUTF8.toList)]

/-- The independently expected business meaning retains units, optionality and normalization. -/
def expected : History where
  id := ⟨"00000000000000000000000000000001"⟩
  timestampNanos := -9223372036854775808
  durationNanos := -1
  exit := 0
  command := "echo λ"
  cwd := "/tmp"
  session := "terminal one"
  origin := ⟨"host", "user:extra"⟩
  author := "user:extra"
  intent := some "  reason  "
  deletedAtNanos := none

/-- All eleven columns decode into a typed domain object with actual source semantics. -/
theorem decoded : decodeOld cells = some expected := by decide +kernel
/-- The typed record meets canonical-ID and signed-number business validity. -/
theorem valid : expected.Valid := by unfold History.Valid; decide +kernel
/-- Physical SQLite identities do not become business identities, but no records are dropped. -/
theorem populated : decodeRows [(-1, cells), (7, cells)] = some [expected, expected] := by decide +kernel
/-- Empty business history is a defined observation. -/
theorem empty : decodeRows [] = some [] := rfl
/-- Host-only author fallback differs deliberately from the origin's default username. -/
theorem legacy_origin : origin "legacy" = ⟨"legacy", "unknown-user"⟩ ∧
    author "legacy" none = "legacy" := by decide +kernel
/-- Nonblank author bytes are not trimmed; Unicode blank intent becomes absent. -/
theorem optional_normalization : author "host:user" (some "  agent  ") = "  agent  " ∧
    nonblank (some "\u0085\u3000") = none := by decide +kernel
/-- An invalid required identifier rejects the whole row, including NULL TEXT primary keys. -/
theorem malformed_id : decodeOld (cells.set 0 (some .null)) = none ∧
    decodeOld (cells.set 0 (some (.text "not-a-uuid".toUTF8.toList))) = none := by decide +kernel
/-- Invalid UTF-8 is rejected rather than replaced with U+FFFD. -/
theorem malformed_utf8 : decodeOld (cells.set 4 (some (.text [0xFF]))) = none := by decide +kernel
/-- This explicit admission subset rejects optional wrong types instead of silently normalizing them. -/
theorem malformed_optional : decodeOld (cells.set 9 (some (.integer 1))) = none := by decide +kernel
/-- Numeric coercion and out-of-i64 values are outside the chosen decoder domain. -/
theorem malformed_numeric : decodeOld (cells.set 1 (some (.text [49]))) = none ∧
    decodeOld (cells.set 1 (some (.integer 9223372036854775808))) = none := by decide +kernel
/-- A bad later row cannot disappear while earlier rows still decode. -/
theorem no_row_filtering : decodeRows [(1, cells), (2, cells.set 0 none)] = none := by decide +kernel
end HistoryDecodingChecks
