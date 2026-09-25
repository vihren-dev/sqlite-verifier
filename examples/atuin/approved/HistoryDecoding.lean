import SqliteVerifier
import HistoryModel

/-! Strict interpretation of canonical stored histories. Required malformed cells
reject the entire observation. Optional fields use the valid TEXT/NULL subdomain
of upstream decoding; no row is filtered out or replacement-decoded. -/
namespace HistoryDecoding
open SqliteVerifier HistoryModel

/-- Decode TEXT strictly; invalid UTF-8 and other storage classes are not strings. -/
def text : Value → Option String
  | .text bytes => String.fromUTF8? ⟨bytes.toArray⟩
  | _ => none

/-- Retain all signed INTEGER values, including negative durations and timestamps. -/
def integer : Value → Option Int
  | .integer value => if signed64 value then some value else none
  | _ => none

/-- Optional cells distinguish SQL NULL from malformed stored data. -/
def optionalText : Value → Option (Option String)
  | .null => some none
  | value => (text value).map some

/-- Deletion times are optional signed Unix nanoseconds, not seconds or dates. -/
def optionalInteger : Value → Option (Option Int)
  | .null => some none
  | value => (integer value).map some

/-- Rust char::is_whitespace uses Unicode White_Space, beyond Lean's ASCII helper. -/
def whitespace (c : Char) : Bool :=
  let n := c.toNat
  (9 ≤ n && n ≤ 13) || (0x2000 ≤ n && n ≤ 0x200A) ||
    [0x20, 0x85, 0xA0, 0x1680, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000].contains n

/-- Upstream tests trim-emptiness but preserves original nonblank text unchanged. -/
def nonblank (value : Option String) : Option String :=
  value.filter (fun s => !s.toList.all whitespace)

/-- Split only at the first colon; additional colons belong to the user component. -/
def originParts (hostname : String) : String × Option String :=
  let chars := hostname.toList
  (String.ofList (chars.takeWhile (· != ':')),
    match chars.dropWhile (· != ':') with
    | [] => none
    | _ :: rest => some (String.ofList rest))

/-- Legacy host-only origins use unknown-user, while author fallback uses the raw host. -/
def origin (hostname : String) : Origin :=
  let (host, user) := originParts hostname
  ⟨host, user.getD "unknown-user"⟩

/-- A blank/missing author uses a parsed user, or the original hostname when no colon exists. -/
def author (hostname : String) (stored : Option String) : String :=
  (nonblank stored).getD ((originParts hostname).2.getD hostname)

/-- Decode exactly the eleven protected pre-migration columns. -/
def decodeOld : List (Option Value) → Option History
  | [some id, some timestamp, some duration, some exit, some command, some cwd,
      some session, some hostname, some deleted, some storedAuthor, some intent] => do
    let id ← text id
    if !canonicalId id then none else do
      let timestamp ← integer timestamp
      let duration ← integer duration
      let exit ← integer exit
      let command ← text command
      let cwd ← text cwd
      let session ← text session
      let hostname ← text hostname
      let deleted ← optionalInteger deleted
      let storedAuthor ← optionalText storedAuthor
      let intent ← optionalText intent
      pure ⟨⟨id⟩, timestamp, duration, exit, command, cwd, session, origin hostname,
        author hostname storedAuthor, nonblank intent, deleted⟩
  | _ => none

/-- Every physical row contributes one business entry or the whole interpretation fails. -/
def decodeRows : List (Int × List (Option Value)) → Option (List History)
  | [] => some []
  | (_, cells) :: rest => do
    let entry ← decodeOld cells
    let entries ← decodeRows rest
    pure (entry :: entries)

/-- Integer decoding establishes the signed business domain. -/
theorem integer_valid (decoded : integer value = some n) : signed64 n = true := by
  unfold integer at decoded
  split at decoded <;> simp_all
  rcases decoded with ⟨valid, rfl⟩
  exact valid

/-- Successful decoding establishes business validity. -/
theorem decodeOld_valid (decoded : decodeOld cells = some entry) :
    entry.Valid := by
  unfold decodeOld at decoded
  split at decoded
  · simp only [bind, Option.bind_eq_some_iff] at decoded
    obtain ⟨id, hid, decoded⟩ := decoded
    split at decoded
    · simp at decoded
    · simp only [pure, Option.bind_eq_some_iff, Option.some.injEq] at decoded
      obtain ⟨timestamp, ht, duration, hd, exit, he, command, hc, cwd, hw,
        session, hs, hostname, hh, deleted, hdel, storedAuthor, ha, intent, hi, rfl⟩ := decoded
      refine ⟨?_, integer_valid ht, integer_valid hd, integer_valid he, ?_⟩
      · simp_all
      · unfold optionalInteger at hdel
        split at hdel
        · cases hdel; rfl
        · simp only [Option.map_eq_some_iff] at hdel
          obtain ⟨n, hn, rfl⟩ := hdel
          exact integer_valid hn
  · simp at decoded

/-- All-row decoding preserves cardinality exactly. -/
theorem decodeRows_length (decoded : decodeRows projected = some entries) :
    entries.length = projected.length := by
  induction projected generalizing entries with
  | nil => simp [decodeRows] at decoded; subst entries; rfl
  | cons pair rest ih =>
    rcases pair with ⟨rowid, cells⟩
    simp only [decodeRows, bind, pure, Option.bind_eq_some_iff, Option.some.injEq] at decoded
    obtain ⟨entry, head, tail, decodedTail, rfl⟩ := decoded
    simp [ih decodedTail]

/-- Every returned business record is valid; no malformed row is skipped. -/
theorem decodeRows_valid (decoded : decodeRows projected = some entries) :
    ∀ entry ∈ entries, entry.Valid := by
  induction projected generalizing entries with
  | nil => simp [decodeRows] at decoded; subst entries; simp
  | cons pair rest ih =>
    rcases pair with ⟨rowid, cells⟩
    simp only [decodeRows, bind, pure, Option.bind_eq_some_iff, Option.some.injEq] at decoded
    obtain ⟨entry, head, tail, decodedTail, rfl⟩ := decoded
    intro item member
    rcases List.mem_cons.mp member with rfl | member
    · exact decodeOld_valid head
    · exact ih decodedTail item member

end HistoryDecoding
