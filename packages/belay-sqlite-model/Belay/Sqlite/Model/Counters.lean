set_option doc.verso true

/-! The three counters of a SQLite connection that {lit}`changes()`, {lit}`total_changes()` and
{lit}`last_insert_rowid()` read (ADR 0024, D1 to D3): what a connection holds between two
statements ({lit}`Counters`), and what one statement does to them
({lit}`Counts`). A counter can be unknown, for a connection that the model
did not see start. -/

namespace Belay.Sqlite.Model

/-- The counters of a connection: SQLite's {lit}`db->nChange`, {lit}`db->nTotalChange` and
{lit}`db->lastRowid`. Each is known or unknown. For example,
{lit}`Counters.newConnection` is a connection that has run no statement, and
{lean}`({} : Counters)` knows none of the three. Use the default, with no counter known, when
the run does not start on a new connection. -/
structure Counters where
  /-- The value of {lit}`changes()`: the rows that the last write changed. -/
  changes : Option Nat := none
  /-- The value of {lit}`total_changes()`: the rows that all writes of the connection changed,
  with the rows of trigger programs and foreign-key actions. -/
  totalChanges : Option Nat := none
  /-- The value of {lit}`last_insert_rowid()`: the rowid of the last row inserted into a table
  with a rowid. -/
  lastInsertRowid : Option Int := none
  deriving DecidableEq, Repr

/-- The counters of a connection that has run no statement: SQLite starts each at 0. -/
def Counters.newConnection : Counters := { changes := some 0, totalChanges := some 0, lastInsertRowid := some 0 }

/-- What one statement does to the counters of its connection. For example, an INSERT of two
rows into a table with rowids gives
{lean}`({ changes := some 2, total := 2, lastRowid := some 5 } : Counts)` when the last row has
rowid 5. The default, with nothing set, is a statement that leaves all three counters. -/
structure Counts where
  /-- The value of {lit}`changes()` after the statement; none when the statement leaves it. -/
  changes : Option Nat := none
  /-- The rows that the statement adds to {lit}`total_changes()`: its own rows and the rows of
  its completed trigger programs and foreign-key actions. -/
  total : Nat := 0
  /-- The value of {lit}`last_insert_rowid()` after the statement; none when the statement
  leaves it. -/
  lastRowid : Option Int := none
  deriving DecidableEq, Repr

/-- The counters after a statement with the counts: {lit}`changes` and the last rowid take the
statement's value when it has one; the total adds the statement's rows, and stays unknown when it
was unknown. -/
def Counters.apply (counters : Counters) (counts : Counts) : Counters :=
  { changes := counts.changes.or counters.changes,
    totalChanges := counters.totalChanges.map (· + counts.total),
    lastInsertRowid := counts.lastRowid.or counters.lastInsertRowid }

/-- For every counters, applying the counts of a statement that leaves the counters gives the
same counters. Proof sketch: the definitions. -/
@[simp] theorem Counters.apply_default (counters : Counters) : counters.apply {} = counters := by
  simp [Counters.apply, Option.or]

/-- The counter that a call of {lit}`changes()`, {lit}`total_changes()` or
{lit}`last_insert_rowid()` reads (ADR 0024, D2). -/
inductive CounterKind where
  /-- {lit}`changes()`. -/
  | changes
  /-- {lit}`total_changes()`. -/
  | totalChanges
  /-- {lit}`last_insert_rowid()`. -/
  | lastInsertRowid
  deriving DecidableEq, Repr

/-- The value of a counter, if the connection knows it. For example, the value of
{lit}`changes()` on {lit}`Counters.newConnection` is 0. -/
def Counters.read (counters : Counters) : CounterKind → Option Int
  | .changes => counters.changes.map Int.ofNat
  | .totalChanges => counters.totalChanges.map Int.ofNat
  | .lastInsertRowid => counters.lastInsertRowid

/-- The counters that a statement reads and that the connection does not know: the first of the
kinds that the statement reads with no value. Use it before the run of the statement: a
statement with an unknown read is not described. -/
def Counters.firstUnknown (counters : Counters) (reads : List CounterKind) : Option CounterKind :=
  reads.find? (counters.read · = none)

/-- The counters as a statement that reads the kinds sees them: the value of each kind that it
reads, and unknown for every other kind. Two connections with the same view for the kinds that a
statement reads run the statement in the same way. For example, a statement that reads only
{lit}`changes()` sees none of the other two counters. -/
def Counters.view (counters : Counters) (reads : List CounterKind) : Counters where
  changes := if reads.contains .changes then counters.changes else none
  totalChanges := if reads.contains .totalChanges then counters.totalChanges else none
  lastInsertRowid := if reads.contains .lastInsertRowid then counters.lastInsertRowid else none

/-- For every counters, the view for a statement that reads no counter knows none of them. Proof
sketch: no kind is in the empty list, so each field is none. -/
@[simp] theorem Counters.view_nil (counters : Counters) : counters.view [] = {} := by
  simp [Counters.view]

/-- For every counters, no counter is unknown for a statement that reads none. Proof sketch: the
empty list has no first element. -/
@[simp] theorem Counters.firstUnknown_nil (counters : Counters) : counters.firstUnknown [] = none := rfl

/-- The first counters know at most what the second know: each counter that the first knows has
the same value in the second. For example, the unknown counters are below every counters. -/
def Counters.LessKnown (first second : Counters) : Prop :=
  (first.changes = none ∨ first.changes = second.changes) ∧
  (first.totalChanges = none ∨ first.totalChanges = second.totalChanges) ∧
  (first.lastInsertRowid = none ∨ first.lastInsertRowid = second.lastInsertRowid)

/-- For every counters and list of kinds, if the first counters know every kind of the list, each
of those kinds has a value in the first counters. Proof sketch: a kind without a value would be
found by {name}`Counters.firstUnknown`. -/
theorem Counters.read_ne_none_of_firstUnknown {counters : Counters} {reads : List CounterKind}
    (known : counters.firstUnknown reads = none) {kind : CounterKind} (member : kind ∈ reads) :
    counters.read kind ≠ none := by
  intro absent
  have := List.find?_eq_none.mp known kind member
  simp [absent] at this

/-- For every pair of counters where the first know at most what the second know, and every kind
that the first counters know, the second counters have the same value for the kind. Proof sketch:
split on the kind; the known value of the first rules out the case that it is unknown. -/
theorem Counters.LessKnown.read_eq {first second : Counters} (less : first.LessKnown second)
    {kind : CounterKind} (known : first.read kind ≠ none) : second.read kind = first.read kind := by
  obtain ⟨changes, total, last⟩ := less
  cases kind <;> simp only [Counters.read] at known ⊢
  · rcases changes with unknown | same
    · simp [unknown] at known
    · rw [same]
  · rcases total with unknown | same
    · simp [unknown] at known
    · rw [same]
  · rcases last with unknown | same
    · exact absurd unknown known
    · exact same.symm

/-- For every pair of counters where the first know at most what the second know, and every list
of kinds that the first counters know: the views for the list ({name}`Counters.view`) are the
same, and the second counters know the list too. Proof sketch: a kind of the list has a value in
the first counters, so the second counters have the same value ({name}`Counters.LessKnown.read_eq`);
a kind outside the list is unknown in both views. -/
theorem Counters.LessKnown.view_eq {first second : Counters} (less : first.LessKnown second)
    {reads : List CounterKind} (known : first.firstUnknown reads = none) :
    first.view reads = second.view reads ∧ second.firstUnknown reads = none := by
  have same : ∀ kind ∈ reads, second.read kind = first.read kind := fun kind member =>
    less.read_eq (Counters.read_ne_none_of_firstUnknown known member)
  refine ⟨?_, ?_⟩
  · have changes : CounterKind.changes ∈ reads → first.changes = second.changes := fun member => by
      have := same _ member
      exact Option.map_injective (fun _ _ => Int.ofNat.inj) this.symm
    have total : CounterKind.totalChanges ∈ reads → first.totalChanges = second.totalChanges := fun member => by
      have := same _ member
      exact Option.map_injective (fun _ _ => Int.ofNat.inj) this.symm
    have last : CounterKind.lastInsertRowid ∈ reads → first.lastInsertRowid = second.lastInsertRowid := fun member => by
      have := same _ member
      exact this.symm
    simp only [Counters.view, Counters.mk.injEq, List.contains_iff_mem]
    exact ⟨by by_cases member : CounterKind.changes ∈ reads <;> simp [member, changes],
      by by_cases member : CounterKind.totalChanges ∈ reads <;> simp [member, total],
      by by_cases member : CounterKind.lastInsertRowid ∈ reads <;> simp [member, last]⟩
  · apply List.find?_eq_none.mpr
    intro kind member unknown
    have := same kind member
    have firstKnown := Counters.read_ne_none_of_firstUnknown known member
    simp only [decide_eq_true_eq] at unknown
    rw [unknown] at this
    exact firstKnown this.symm

/-- For every pair of counters where the first know at most what the second know, and every
counts: the first counters after the counts know at most what the second counters after the counts
know. Proof sketch: a value that the counts set is the same on both sides; otherwise the value of
the first counters is unknown or the same as the second, and the total adds the same number. -/
theorem Counters.LessKnown.apply {first second : Counters} (less : first.LessKnown second) (counts : Counts) :
    (first.apply counts).LessKnown (second.apply counts) := by
  obtain ⟨changes, total, last⟩ := less
  refine ⟨?_, ?_, ?_⟩
  · rcases h : counts.changes with _ | value
    · simpa [Counters.apply, h] using changes
    · simp [Counters.apply, h]
  · rcases total with h | h <;> simp [Counters.apply, h]
  · rcases h : counts.lastRowid with _ | value
    · simpa [Counters.apply, h] using last
    · simp [Counters.apply, h]

end Belay.Sqlite.Model
