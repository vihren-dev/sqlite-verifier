import Std

/-! Application history independent of SQLite rows, schemas, and migration machinery.
This example admits canonical UUID spelling and the signed nanosecond domain used
by Atuin's database decoder; it does not implement every UUID text spelling. -/
namespace HistoryModel

/-- The application's UUID identity, never SQLite's physical rowid. -/
structure HistoryId where
  canonical : String
  deriving Repr, DecidableEq

/-- Atuin command origins separate machine and user names. -/
structure Origin where
  host : String
  user : String
  deriving Repr, DecidableEq

/-- The business fields at the selected shell migration, before later author_kind. -/
structure History where
  id : HistoryId
  timestampNanos : Int
  durationNanos : Int
  exit : Int
  command : String
  cwd : String
  session : String
  origin : Origin
  author : String
  intent : Option String
  deletedAtNanos : Option Int
  shell : Option String
  deriving Repr, DecidableEq

/-- SQLite INTEGER and Atuin's i64 nanosecond conversion share this exact range. -/
def signed64 (value : Int) : Bool := decide (-(2 ^ 63 : Int) ≤ value ∧ value < 2 ^ 63)

/-- Canonical lowercase simple UUID text is emitted by upstream HistoryId::to_string. -/
def canonicalId (value : String) : Bool :=
  value.length == 32 && value.toList.all (fun c =>
    ('0' ≤ c && c ≤ '9') || ('a' ≤ c && c ≤ 'f'))

/-- Domain validity does not invent positivity, UUID session constraints or nonempty shell. -/
def History.Valid (history : History) : Prop :=
  canonicalId history.id.canonical = true ∧ signed64 history.timestampNanos = true ∧
  signed64 history.durationNanos = true ∧ signed64 history.exit = true ∧
  history.deletedAtNanos.all signed64 = true

end HistoryModel
