import Belay.Sqlite.Model.KeysUniqueRuns
import Belay.Sqlite.Model.KeysUniqueExamples
import Belay.Sqlite.Model.ForeignKeyExamples

set_option doc.verso true

/-! Examples of the run theorem of the atom "keys unique" (ADR 0022, slice 2), each checked by the
kernel: the theorem applied to a resolved script with an INSERT, an upsert, a DELETE that
cascades and a ROLLBACK, and finding 1 of the keys-unique status file as a run whose outcome
breaks the atom without the run conditions. -/

namespace Belay.Sqlite.Model.KeysUniqueRunExamples

open Belay.Sqlite.Model Syntax Resolution.Examples
open Belay.Sqlite.Model.ForeignKeyExamples (keysOn schema deleteOne)
open Belay.Sqlite.Model.KeysUniqueExamples (tableOnly filterPastWidthIndex columnFive)

/-- With foreign keys on: {lit}`CREATE TABLE p(id PRIMARY KEY)`, the child
{lit}`c(x REFERENCES p ON DELETE CASCADE)`, the INSERT of the rows 1 and 2 of {lit}`p` and 1 of
{lit}`c`, then {lit}`BEGIN`, the upsert {lit}`INSERT INTO p VALUES(1) ON CONFLICT DO NOTHING`,
{lit}`DELETE FROM p WHERE id = 1`, which deletes the row of {lit}`c`, and {lit}`ROLLBACK`. -/
def cascadeSyntax : List Syntax.Statement :=
  schema .cascade .noAction ++
    [.begin, .insert (name! "p") none [[.numeric "1"]] [{ target := none, action := .nothing }], deleteOne, .rollback]

/-- The resolved statements of {name}`cascadeSyntax` from the empty catalog, without values. -/
def cascadeScript : List (Resolved.Statement × List Value) :=
  bindValues (statements (migration [] cascadeSyntax keysOn)) []

-- The script resolves to its eight statements. Before ROLLBACK, the upsert has kept the two rows
-- of `p`, and the DELETE has deleted the row 1 of `p` and, by the cascade, the row of `c`. The
-- run succeeds, and ROLLBACK restores the row of `c`.
example : cascadeScript.length = 8 ∧
    (match runSql (cascadeScript.take 7) {} with
      | .pending _ visible none =>
        (visible.rows.getD 0 []).map (·.values) == [[.integer 2]] && (visible.rows.getD 1 []).isEmpty
      | .pending _ _ (some _) | .success _ | .failure .. => false) = true ∧
    (match runSql cascadeScript {} with
      | .success database => (database.rows.getD 1 []).map (·.values) == [[.integer 1]]
      | .failure .. | .pending .. => false) = true := by decide +kernel

/-- The run theorem applied to {name}`cascadeScript`: each database of the outcome of
{name}`runSql` from the empty database satisfies {name}`Database.KeysUnique`. The script has no
CREATE INDEX, ADD COLUMN or DROP, so it meets {name}`RunConditions`
({name}`RunConditions.of_unconditioned`). -/
theorem cascadeScript_keysUnique : (runSql cascadeScript {}).KeysUnique :=
  runSql_keysUnique cascadeScript (by decide +kernel) (RunConditions.of_unconditioned _ _ _ (by decide +kernel))

/-- Finding 1 as a run: the resolved CREATE INDEX of the index of
{lit}`KeysUniqueExamples.filterPastWidth`, whose filter reads past the width of {lit}`t`, then
ADD COLUMN with the default 5, from the table {lit}`t(a)` with two equal rows. -/
def findingScript : List (Resolved.Statement × List Value) :=
  [(.createIndex 1 (name! "i") filterPastWidthIndex, []), (.addColumn 0 columnFive, [])]

-- The start database keeps the keys unique, and the outcome of the run does not: the run
-- theorem of `runSql` needs its run conditions (the CREATE INDEX does not meet its condition).
example : tableOnly.KeysUnique ∧ ¬(runSql findingScript tableOnly).KeysUnique := by decide +kernel

end Belay.Sqlite.Model.KeysUniqueRunExamples
