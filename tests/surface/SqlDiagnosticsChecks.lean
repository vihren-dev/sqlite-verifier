import Belay

/-! A fixture of `tests/surface_guide_test.py`: checks of the pure part of `sql!`. They cover
`Span.select` and `Span.leaves` of the text package (`Translation/Located.lean`), the name search
`nameRange?` and the diagnostics `scriptDiagnostics` of `Belay/Sqlite/SqlDiagnostics.lean`, as
byte ranges of the SQL text, and `PrepareError.name?` of the model
(`Resolution/ErrorNames.lean`). The file fails to elaborate when a check fails. -/

open Belay.Sqlite Belay.Sqlite.Model Belay.Sqlite.Translation

/-- The spans of the text `t.a = 'a'`: a comparison of the qualified name `t.a`, as two leaves,
and of a string literal. -/
def comparison : Span :=
  { start := 0, stop := 9, parts := #[{ start := 0, stop := 3, parts := #[{ start := 0, stop := 1 },
      { start := 2, stop := 3 }] }, { start := 6, stop := 9 }] }

-- A path selects the deepest node on it; a step past the known parts stops at the node before it.
#guard comparison.select [] == (0, 9)
#guard comparison.select [0, 1] == (2, 3)
#guard comparison.select [0, 1, 4] == (2, 3)
#guard comparison.select [5] == (0, 9)
#guard comparison.leaves == #[(0, 1), (2, 3), (6, 9)]

-- The name search: a qualified name matches a leaf, a dot and a leaf, and a string literal names
-- nothing.
#guard nameRange? "t.a = 'a'".toUTF8 comparison (name! "T.A") == some (0, 3)
#guard nameRange? "t.a = 'a'".toUTF8 comparison (name! "a") == some (2, 3)
#guard nameRange? "x.y = 'b'".toUTF8 comparison (name! "b") == none
#guard (PrepareError.expression (.noSuchColumn (name! "nmae"))).name? == some (name! "nmae")
#guard (PrepareError.expression .valuesDiffer).name? == none

/-- The ranges that the name search gives for each name in the first statement of the translated
text ({name}`nameRange?`). -/
def nameRangesOf (text : String) (names : List Identifier) : IO (List (Option (Nat × Nat))) := do
  match ← translateText text with
  | .ok items => return names.map (nameRange? text.toUTF8 (items[0]?.map (·.statement.span)).get!)
  | .error refusal => throw <| IO.userError s!"the translation refuses {text}: {refusal.message}"

-- In a translated text, where a leaf can cover a whole expression: a qualified name in JOIN ... ON,
-- each side of LIKE, a name in a string literal, and a name written twice.
/-- info: [some (26, 30), some (33, 37), some (22, 25), some (31, 32), none, none] -/
#guard_msgs in
#eval do
  return (← nameRangesOf "SELECT 1 FROM t JOIN u ON t.a1 = u.b1" [name! "t.a1", name! "u.b1"]) ++
    (← nameRangesOf "SELECT a FROM t WHERE lhs LIKE 'x'" [name! "lhs"]) ++
    (← nameRangesOf "SELECT a FROM t WHERE 'x' LIKE b" [name! "b", name! "x"]) ++
    (← nameRangesOf "SELECT a AS a FROM t" [name! "a"])

/-- The diagnostics of the text against the empty database, as byte ranges and messages. -/
def diagnosticsOf (text : String) : IO (List Diagnostic) := do
  match ← translateText text with
  | .ok items => return scriptDiagnostics Database.empty.raw.connection.resolveState text.toUTF8 (items.toList.map (·.statement))
  | .error refusal => throw <| IO.userError s!"the translation refuses {text}: {refusal.message}"

/--
info: [{ start := 26, stop := 30, message := "no such column: nmae" },
 { start := 53, stop := 54, message := "no such table: u" }]
-/
#guard_msgs in
#eval diagnosticsOf "CREATE TABLE t(a); SELECT nmae FROM t; SELECT a FROM u"

-- An error without a name in its message is at the statement.
/-- info: [{ start := 19, stop := 51, message := "all VALUES must have the same number of terms" }] -/
#guard_msgs in
#eval diagnosticsOf "CREATE TABLE t(a); INSERT INTO t VALUES (1), (1, 2)"

-- A prepare error before the first restriction, then the restriction at its node; the statements
-- after the restriction are not resolved.
/--
info: [{ start := 26, stop := 27, message := "no such column: b" },
 { start := 46,
   stop := 51,
   message := "the rowid names rowid, _rowid_ and oid are not modeled in expressions over a table, or as the SET column of a table without an INTEGER PRIMARY KEY; name the table's columns" }]
-/
#guard_msgs in
#eval diagnosticsOf "CREATE TABLE t(a); SELECT b FROM t; SELECT a, rowid FROM t; SELECT c FROM t"
