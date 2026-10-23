import Belay

/-! A fixture of `tests/surface_programs_test.py`: the errors of programs and of the clock
(`Belay/Sqlite/ProgramQueries.lean`, `Belay/Sqlite/Env.lean`), each at its position. `query` and
`single` of a script that is not one statement are an error at the function, also for a script
with a `$x` value; Lean adds the first message for an argument whose tactic fails. `clockAt` of a
text that SQLite's date functions do not read as a time is an error at the text: a date that does
not exist, `now`, which reads the clock, and a text that is not a date. The file fails to
elaborate when a message or its position is not the expected one. -/

open Belay.Sqlite

/--
@ +1:50...55
error: could not synthesize default value for parameter 'one' using tactics
---
@ +1:50...55
error: query and single take a script of exactly one statement; send the other statements with send, or write each one in its own query
-/
#guard_msgs (positions := true) in
example : Sql (Except Nat (List (List Value))) := query (sql r"SELECT 1; SELECT 2")

/--
@ +1:44...50
error: could not synthesize default value for parameter 'one' using tactics
---
@ +1:44...50
error: query and single take a script of exactly one statement; send the other statements with send, or write each one in its own query
-/
#guard_msgs (positions := true) in
example (x : Value) : Sql (Option Value) := single (sql r"SELECT $x; SELECT 2")

-- A script of one statement with a `$x` value passes the check.
example (x : Value) : Sql (Option Value) := single (sql r"SELECT $x")

/--
@ +1:25...46
error: SQLite's date functions do not read the text "2026-02-30 25:00:00" as a time; write a date and a time in UTC, such as "2026-10-20 12:00:00"
-/
#guard_msgs (positions := true) in
example : Env := clockAt "2026-02-30 25:00:00"

/--
@ +1:25...30
error: SQLite's date functions do not read the text "now" as a time; write a date and a time in UTC, such as "2026-10-20 12:00:00"
-/
#guard_msgs (positions := true) in
example : Env := clockAt "now"

/--
@ +1:25...35
error: SQLite's date functions do not read the text "tomorrow" as a time; write a date and a time in UTC, such as "2026-10-20 12:00:00"
-/
#guard_msgs (positions := true) in
example : Env := clockAt "tomorrow"
