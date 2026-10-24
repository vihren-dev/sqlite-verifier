import Belay.Sqlite.Model.Resolution.GeneratedExamples
import Belay.Sqlite.Model.Resolution.IndexExamples

set_option doc.verso true

/-! Examples of the functions that are not deterministic in schema positions (ADR 0024, D5),
checked by {lit}`#guard` when the package builds. The five functions {lit}`changes()`,
{lit}`total_changes()`, {lit}`last_insert_rowid()`, {lit}`random()` and {lit}`randomblob(n)` give
SQLite's prepare error in a generated column, an index expression and the filter of a partial
index, alone and inside an expression. The order of SQLite's walk of names (checked natively with
SQLite 3.51.0) decides which error it reports when the expression has another error, and the model
has a restriction for that. A
{lit}`CHECK` and a {lit}`DEFAULT` accept the functions in SQLite, and the model has a restriction
there. -/

namespace Belay.Sqlite.Model.Resolution.NondeterministicExamples

open Belay.Sqlite.Model Syntax Belay.Sqlite.Model.Resolution.Examples
open Belay.Sqlite.Model.Resolution.GeneratedExamples (gen ref)
open Belay.Sqlite.Model.Resolution.IndexExamples (indexD term)

/-- The prepare error of {lit}`CREATE TABLE n(a INTEGER, b AS (expression))`, or none. -/
def generatedError (expression : Expr) : Option PrepareError :=
  match statements (migration [] [.createTable (name! "n") [column (name! "a") (some "INTEGER"), gen (name! "b") expression] []]) with
  | [.prepareError error] => some error
  | _ => none

/-- The prepare error of {lit}`CREATE INDEX i ON d(expression)`, or none. -/
def indexError (expression : Expr) : Option PrepareError :=
  match statements (migration IndexExamples.tableD [indexD [term expression]]) with
  | [.prepareError error] => some error
  | _ => none

/-- The prepare error of {lit}`CREATE INDEX i ON d(a) WHERE expression`, or none. -/
def filterError (expression : Expr) : Option PrepareError :=
  match statements (migration IndexExamples.tableD [indexD [key (name! "a")] (some expression)]) with
  | [.prepareError error] => some error
  | _ => none

/-- The reason of the restriction of {lit}`CREATE TABLE n(a, b AS (expression))`. -/
def generatedReason (expression : Expr) : String :=
  reason (migration [] [.createTable (name! "n") [column (name! "a") (some "INTEGER"), gen (name! "b") expression] []])

/-- The call {lit}`changes()`. -/
def changes : Expr := .call "changes" []
/-- The call {lit}`total_changes()`. -/
def totalChanges : Expr := .call "total_changes" []
/-- The call {lit}`last_insert_rowid()`. -/
def lastInsertRowid : Expr := .call "last_insert_rowid" []
/-- The call {lit}`random()`. -/
def random : Expr := .call "random" []
/-- The call {lit}`randomblob(1)`. -/
def randomblob : Expr := .call "randomblob" [.numeric "1"]

/-- The column {lit}`a` of the tables of the examples. -/
def a : Expr := .identifier (name! "a") .none
/-- A name that is no column of the tables of the examples. -/
def missing : Expr := .identifier (name! "nosuch") .none

-- Each function gives the error of its position, alone.
#guard [changes, totalChanges, lastInsertRowid, random, randomblob].all fun call =>
  generatedError call == some (.expression .nondeterministicGenerated)
#guard [changes, totalChanges, lastInsertRowid, random, randomblob].all fun call =>
  indexError call == some (.expression (.nondeterministicIndex false))
#guard [changes, totalChanges, lastInsertRowid, random, randomblob].all fun call =>
  filterError call == some (.expression (.nondeterministicIndex true))

-- Inside an expression, as the argument of a function, and in an argument of randomblob.
#guard generatedError (.arithmetic .add a changes) == some (.expression .nondeterministicGenerated)
#guard indexError (.call "abs" [changes]) == some (.expression (.nondeterministicIndex false))
#guard filterError (.compare .gt a (.call "abs" [random])) == some (.expression (.nondeterministicIndex true))
#guard generatedError (.call "randomblob" [a]) == some (.expression .nondeterministicGenerated)
#guard generatedError (.call "Changes" []) == some (.expression .nondeterministicGenerated)

-- A missing column in the same expression is a restriction in every position and order: SQLite
-- reports the missing column for {lit}`nosuch + changes()` and the call for {lit}`abs(nosuch) + changes()`.
#guard generatedReason (.arithmetic .add changes missing) == RestrictionKind.nondeterministicErrorOrder.message
#guard generatedReason (.arithmetic .add missing changes) == RestrictionKind.nondeterministicErrorOrder.message
#guard generatedReason (.arithmetic .add (.call "abs" [missing]) changes) ==
  RestrictionKind.nondeterministicErrorOrder.message
#guard reason (migration IndexExamples.tableD [indexD [term (.arithmetic .add missing random)]]) ==
  RestrictionKind.nondeterministicErrorOrder.message
#guard reason (migration IndexExamples.tableD [indexD [key (name! "a")] (some (.compare .gt randomblob missing))]) ==
  RestrictionKind.nondeterministicErrorOrder.message
-- Without a call, a missing column is still SQLite's error.
#guard indexError missing == some (.expression (.noSuchColumn (name! "nosuch")))

-- A call with the wrong number of arguments is not one of these calls.
#guard generatedError (.call "changes" [a]) != some (.expression .nondeterministicGenerated)
#guard generatedError (.call "random" [a]) != some (.expression .nondeterministicGenerated)

-- Another error of the walk in the same expression is a restriction, in either order.
#guard generatedReason (.arithmetic .add changes (.call "count" [a])) ==
  RestrictionKind.nondeterministicErrorOrder.message
#guard generatedReason (.arithmetic .add (.call "count" [a]) changes) ==
  RestrictionKind.nondeterministicErrorOrder.message

-- A CHECK keeps its restriction: the model does not describe random() or the counters there.
#guard (match migration [] [.createTable (name! "c") [column (name! "a") (some "INTEGER")]
    [.check (.compare .gt random (.numeric "0")) ""]] with
  | .restricted _ => true
  | .resolved .. => false)

end Belay.Sqlite.Model.Resolution.NondeterministicExamples
