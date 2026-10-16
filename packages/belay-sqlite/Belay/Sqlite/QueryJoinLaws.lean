import Belay.Sqlite.QueryLaws
import Belay.Sqlite.QueryJoins

set_option doc.verso true

/-! Laws of joined sources (ADR 0012, amendments 2 and 3, "Proofs"): a query without
joins reads the rows of its one table, every joined row has the width of its tables
together, a left or full join keeps every left row, and a right or full join keeps every
right row. -/

namespace Belay.Sqlite.Resolved

/-- For every query of a table without joins and every database, the source rows of the
query are the rows of its table in rowid order ({name}`sourceRows`), or none when the
table is missing: the query of one table is the special case of a join. -/
theorem Query.source_single (query : Query) (database : Database) (table : Nat) (first : query.table = some table)
    (single : query.joins = []) : query.source database = (database table).map sourceRows := by
  simp only [Query.source, first, single]
  cases database table <;> rfl

/-- For every query without a table ({lit}`SELECT` without {lit}`FROM`) and every
database, the source is one row with no cells. -/
theorem Query.source_none (query : Query) (database : Database) (none_ : query.table = none) :
    query.source database = some [[]] := by
  simp only [Query.source, none_]
  rfl

/-- For every valid table, every row of {name}`sourceRows` has one cell per column.
Proof sketch: the sorted rows are a permutation of the table's rows
({name}`stableSort_perm`), each of which has one cell per column. -/
theorem sourceRows_width {table : Table} (valid : table.Valid) :
    ∀ cells ∈ sourceRows table, cells.length = table.shape.columns.length := by
  intro cells member
  obtain ⟨row, sorted, rfl⟩ := List.mem_map.mp member
  exact (valid.2 row ((stableSort_perm _ _).mem_iff.mp sorted)).2.1

/-- For every width, left row of that width, join and valid table, every row of
{name}`joinMatches` has the width plus one cell per column of the table. Proof sketch: a
match is the left row followed by a row of {name}`sourceRows`, whose width is
{name}`sourceRows_width`. -/
theorem joinMatches_width {width : Nat} {row : List Value} {table : Table} (join : Join) (valid : table.Valid)
    (rowWidth : row.length = width) :
    ∀ joined ∈ joinMatches row join table, joined.length = width + table.shape.columns.length := by
  intro joined member
  obtain ⟨cells, cellsMember, built⟩ := List.mem_filterMap.mp member
  dsimp only at built
  split at built <;> cases built
  simp [rowWidth, sourceRows_width valid cells cellsMember]

/-- For every width, left row of that width, join and valid table, every row of
{name}`joinRow` has the width plus one cell per column of the table: a match by
{name}`joinMatches_width`, or the left row padded with one NULL per column. -/
theorem joinRow_width {width : Nat} {leftRow : List Value} {table : Table} (join : Join) (valid : table.Valid)
    (rowWidth : leftRow.length = width) :
    ∀ row ∈ joinRow join table leftRow, row.length = width + table.shape.columns.length := by
  intro row joined
  have matched := joinMatches_width join valid rowWidth
  unfold joinRow at joined
  cases kind : join.kind <;> simp only [kind] at joined
  · exact matched row joined
  all_goals first
    | exact matched row joined
    | by_cases empty : (joinMatches leftRow join table).isEmpty
      · simp only [empty, ite_true, List.mem_singleton] at joined
        subst joined
        simp [rowWidth]
      · simp only [empty, Bool.false_eq_true, ite_false] at joined
        exact matched row joined

/-- For every width, left rows of that width, join and valid table, every row of
{name}`joinRows` has the width plus one cell per column of the table: a joined row is a
left row followed by a row of the table or by NULL padding, or, for a right or full
join, NULL padding of the width followed by a row of the table. Proof sketch: a row of
the first part has the width by {name}`joinRow_width`; an added right row is a row of
{name}`sourceRows`, whose width is {name}`sourceRows_width`, after the width's NULLs. -/
theorem joinRows_width {width : Nat} {left : List (List Value)} {table : Table} (join : Join)
    (valid : table.Valid) (widths : ∀ row ∈ left, row.length = width) :
    ∀ row ∈ joinRows width left join table, row.length = width + table.shape.columns.length := by
  intro row member
  unfold joinRows at member
  rcases List.mem_append.mp member with joined | added
  · obtain ⟨leftRow, leftMember, joined⟩ := List.mem_flatMap.mp joined
    exact joinRow_width join valid (widths leftRow leftMember) row joined
  · cases kind : join.kind <;> simp only [kind, List.not_mem_nil] at added
    all_goals
      obtain ⟨cells, unmatched, rfl⟩ := List.mem_map.mp added
      simp [sourceRows_width valid cells (List.mem_filter.mp unmatched).1]

/-- For every left or full join, width, left rows and table, every left row is a prefix of
some row of {name}`joinRows`: such a join drops no left row. Proof sketch: a left row with
matches is the prefix of its first match; otherwise it is the prefix of its padded row. -/
theorem joinRows_left_keeps {width : Nat} {left : List (List Value)} {table : Table} (join : Join)
    (kind : join.kind = .left ∨ join.kind = .full) :
    ∀ leftRow ∈ left, ∃ row ∈ joinRows width left join table, leftRow <+: row := by
  intro leftRow member
  have joined : ∀ row ∈ joinRow join table leftRow, row ∈ joinRows width left join table :=
    fun row inner => List.mem_append_left _ (List.mem_flatMap.mpr ⟨leftRow, member, inner⟩)
  have padded : joinRow join table leftRow = if (joinMatches leftRow join table).isEmpty
      then [leftRow ++ List.replicate table.shape.columns.length .null] else joinMatches leftRow join table := by
    rcases kind with kind | kind <;> simp [joinRow, kind]
  by_cases empty : (joinMatches leftRow join table).isEmpty
  · refine ⟨leftRow ++ List.replicate table.shape.columns.length .null, joined _ ?_, List.prefix_append _ _⟩
    simp [padded, empty]
  · obtain ⟨row, rowMember⟩ := List.exists_mem_of_ne_nil (joinMatches leftRow join table) (by simpa using empty)
    obtain ⟨cells, _, built⟩ := List.mem_filterMap.mp rowMember
    dsimp only at built
    split at built <;> cases built
    refine ⟨leftRow ++ cells, joined _ ?_, List.prefix_append _ _⟩
    simp only [padded, empty, Bool.false_eq_true, ite_false]
    exact rowMember

/-- For every right or full join, width, left rows and table, every row of the table is a
suffix of some row of {name}`joinRows`: such a join drops no right row. Proof sketch: a
row that some left row matches ends that left row's match; a row that no left row matches
is in {name}`unmatchedRight` and ends its padded row. -/
theorem joinRows_right_keeps {width : Nat} {left : List (List Value)} {table : Table} (join : Join)
    (kind : join.kind = .right ∨ join.kind = .full) :
    ∀ cells ∈ sourceRows table, ∃ row ∈ joinRows width left join table, cells <:+ row := by
  intro cells member
  by_cases found : left.any fun row => join.matches (row ++ cells)
  · obtain ⟨leftRow, leftMember, matched⟩ := List.any_eq_true.mp found
    have isMatch : leftRow ++ cells ∈ joinMatches leftRow join table :=
      List.mem_filterMap.mpr ⟨cells, member, by simp [matched]⟩
    have inRow : leftRow ++ cells ∈ joinRow join table leftRow := by
      have nonempty : (joinMatches leftRow join table).isEmpty = false :=
        List.isEmpty_eq_false_iff_exists_mem.mpr ⟨_, isMatch⟩
      rcases kind with kind | kind <;> simp only [joinRow, kind, nonempty, Bool.false_eq_true, ite_false] <;>
        exact isMatch
    exact ⟨leftRow ++ cells, List.mem_append_left _ (List.mem_flatMap.mpr ⟨leftRow, leftMember, inRow⟩),
      List.suffix_append _ _⟩
  · have unmatched : cells ∈ unmatchedRight left join table := List.mem_filter.mpr ⟨member, by simpa using found⟩
    refine ⟨List.replicate width .null ++ cells, ?_, List.suffix_append _ _⟩
    unfold joinRows
    rcases kind with kind | kind <;> simp only [kind] <;>
      exact List.mem_append_right _ (List.mem_map.mpr ⟨cells, unmatched, rfl⟩)

end Belay.Sqlite.Resolved
