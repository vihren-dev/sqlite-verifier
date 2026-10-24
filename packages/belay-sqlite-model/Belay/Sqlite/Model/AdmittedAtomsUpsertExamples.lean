import Belay.Sqlite.Model.AdmittedUpsertRows
import Belay.Sqlite.Model.UpsertExamples

set_option doc.verso true

/-! Examples of where the rows of an upsert come from (ADR 0022, slice 4, part 2), each checked by the
kernel: the three origins of {lit}`LiteralData.UpsertOrigin` on the table of {lit}`UpsertExamples`, and a
row that has none of them. -/

namespace Belay.Sqlite.Model.AdmittedAtomsUpsertExamples

open Belay.Sqlite.Model UpsertExamples

/-- The proposed row of the values {lit}`(3, 3, 'c')`. -/
def proposed : Row := LiteralData.proposedRow table [.integer 3, .integer 3, letter 99]

-- A row of the table is an origin, with any clauses.
example : LiteralData.UpsertOrigin (.plain 0) [] table proposed ⟨1, [.integer 1, .integer 1, letter 97]⟩ :=
  .inl (by decide +kernel)

-- The proposed row is an origin.
example : LiteralData.UpsertOrigin (.plain 0) [] table proposed proposed := .inr (.inl rfl)

-- The row that {lit}`ON CONFLICT(k) DO UPDATE SET v = excluded.v` writes for the existing row at rowid 1 is
-- an origin: it keeps the rowid and takes the proposed value of {lit}`v`.
example : LiteralData.UpsertOrigin (.plain 0) [setV [0] excludedV] table proposed
    ⟨1, [.integer 1, .integer 1, letter 99]⟩ :=
  .inr (.inr ⟨⟨1, [.integer 1, .integer 1, letter 97]⟩, by decide +kernel, [(2, excludedV)],
    ⟨setV [0] excludedV, by simp, none, rfl⟩, by decide +kernel, by decide +kernel⟩)

-- A row with an unknown rowid and values is no origin when there is no clause: it is not a row of the
-- table, and it is not the proposed row.
example : ¬ LiteralData.UpsertOrigin (.plain 0) [] table proposed ⟨9, [.integer 9, .integer 9, letter 100]⟩ := by
  rintro (member | same | ⟨_, _, _, ⟨clause, inClauses, _⟩, _⟩)
  · revert member; decide +kernel
  · revert same; decide +kernel
  · simp at inClauses

end Belay.Sqlite.Model.AdmittedAtomsUpsertExamples
