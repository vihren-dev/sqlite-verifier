import Belay.Sqlite.Model.CompoundExamples
import Belay.Sqlite.Model.StatementStep

set_option doc.verso true

/-! Checked examples of the failures of a compound {lit}`SELECT` (ADR 0019, D3): where SQLite
runs a term, where it reads {lit}`LIMIT` and {lit}`OFFSET`, and when a failure is certain. The
probes are those of outcome 10 of the task file of slice 3, checked natively. The failing term is
{lit}`SELECT abs(-9223372036854775808)`; a fault {lit}`Fault.must` is the statement's
{lit}`integer overflow` error. -/

namespace Belay.Sqlite.Model.Resolved.CompoundExamples

/-- The term that fails. -/
def failingTerm : Query := literals [failing]

-- SELECT 1 INTERSECT SELECT 2 INTERSECT SELECT abs(...) gives no error: the left rows are empty.
example : runOf (compound [.intersect, .intersect] [.binary]) [literals [int 1], literals [int 2], failingTerm] =
    some ([], .none, false, false) := by decide +kernel
-- SELECT 1 WHERE 0 EXCEPT SELECT abs(...) gives no error either.
example : runOf (compound [.except] [.binary]) [{ literals [int 1] with filter := some (int 0) }, failingTerm] =
    some ([], .none, false, false) := by decide +kernel
-- SELECT 1 UNION ALL SELECT abs(...) LIMIT 1 gives 1: the LIMIT is full before the right term.
example : runOf { compound [.unionAll] [.binary] with limit := some 1 } [literals [int 1], failingTerm] =
    some ([[.integer 1]], .none, false, false) := by decide +kernel
-- With UNION it fails: SQLite runs both terms before it reads the LIMIT.
example : (runOf { compound [.union] [.binary] with limit := some 1 } [literals [int 1], failingTerm]).map (·.2.1) =
    some .must := by decide +kernel
-- SELECT 1 INTERSECT SELECT abs(...) LIMIT 0 gives no error: INTERSECT reads the LIMIT first.
example : runOf { compound [.intersect] [.binary] with limit := some 0 } [literals [int 1], failingTerm] =
    some ([], .none, false, false) := by decide +kernel
-- SELECT abs(...) UNION SELECT 1 UNION ALL SELECT 2 LIMIT 0 fails: the UNION reads the LIMIT.
example : (runOf { compound [.union, .unionAll] [.binary] with limit := some 0 }
    [failingTerm, literals [int 1], literals [int 2]]).map (·.2.1) = some .must := by decide +kernel
-- SELECT abs(...) UNION ALL SELECT 1 LIMIT 0 gives no error: SQLite reads the LIMIT first.
example : runOf { compound [.unionAll] [.binary] with limit := some 0 } [failingTerm, literals [int 1]] =
    some ([], .none, false, false) := by decide +kernel
-- SELECT 1 UNION ALL SELECT abs(...): SQLite gives the row 1 before the error, which the model
-- does not describe.
example : (runOf (compound [.unionAll] [.binary]) [literals [int 1], failingTerm]).map (·.2.1) = some .may := by
  decide +kernel
-- With ORDER BY, SQLite merges the sorted terms and can stop early: a failure is not certain.
example : (runOf { compound [.union] [.binary] with orderBy := [{ key := .output 0 }] }
    [literals [int 1], failingTerm]).map (·.2.1) = some .may := by decide +kernel

/-- The value {lit}`'x'` for {lit}`LIMIT ?`, which is not an integer. -/
def notInteger : List Value := [.text [120]]

-- SELECT 1 UNION SELECT 2 LIMIT ?1 with 'x': datatype mismatch after both terms.
example : runOf { compound [.union] [.binary] with limitParameter := some 1 } [literals [int 1], literals [int 2]] notInteger =
    some ([], .none, false, true) := by decide +kernel
-- SELECT abs(...) UNION SELECT 1 LIMIT ?1 with 'x': the term fails before SQLite reads the LIMIT.
example : (runOf { compound [.union] [.binary] with limitParameter := some 1 } [failingTerm, literals [int 1]]
    notInteger).map (·.2.1) = some .must := by decide +kernel
-- SELECT abs(...) UNION ALL SELECT 1 LIMIT ?1 with 'x': SQLite reads the LIMIT first.
example : runOf { compound [.unionAll] [.binary] with limitParameter := some 1 } [failingTerm, literals [int 1]]
    notInteger = some ([], .none, false, true) := by decide +kernel
-- SELECT 1 INTERSECT SELECT abs(...) LIMIT ?1 with 'x': INTERSECT reads the LIMIT before its right term.
example : runOf { compound [.intersect] [.binary] with limitParameter := some 1 } [literals [int 1], failingTerm]
    notInteger = some ([], .none, false, true) := by decide +kernel

/-- {lit}`SELECT (compound)` with the compound as subquery 0 and its terms after it. -/
def scalarStatement : Query := { literals [.subquery 0] with names := ["s"] }

/-- A compound subquery at index 0 over the terms at indexes 1 to n. -/
def subqueryCompound (operators : List CompoundOperator) : Query :=
  let rest := operators.zipIdx.map fun (operator, index) => (operator, index + 2)
  let terms : Compound := { first := 1, rest, collations := [.binary] }
  { compound operators [.binary] with compound := some terms }

-- SELECT (SELECT 2 UNION SELECT 1 ORDER BY 1 DESC) is 2.
example : runOf scalarStatement [{ subqueryCompound [.union] with orderBy := [{ key := .output 0, descending := true }] },
    literals [int 2], literals [int 1]] = some ([[.integer 2]], .none, false, false) := by decide +kernel
-- SELECT (SELECT 2 UNION SELECT 1) is not described: SQLite's plan chooses the first row.
example : (runOf scalarStatement [subqueryCompound [.union], literals [int 2], literals [int 1]]).map (·.2.1) =
    some .may := by decide +kernel
-- SELECT 1 IN (SELECT 2 UNION SELECT 1) is 1.
example : runOf (literals [.inQuery (int 1) 0 none .binary false]) [subqueryCompound [.union], literals [int 2], literals [int 1]] =
    some ([[.integer 1]], .none, false, false) := by decide +kernel

-- The model describes a compound statement whose term certainly fails
-- ({name}`statementReady`): the compound describes the failures of its terms.
example : statementReady 0 [] (.query (compound [.union] [.binary]) [literals [int 1], failingTerm]) (.ofTables []) =
    true := by decide +kernel
-- It does not describe a compound whose term names a subquery with a call that can fail.
example : statementReady 0 [] (.query (compound [.union] [.binary])
    [literals [.subquery 2], literals [int 1], literals [failing]]) (.ofTables []) =
    false := by decide +kernel

end Belay.Sqlite.Model.Resolved.CompoundExamples
