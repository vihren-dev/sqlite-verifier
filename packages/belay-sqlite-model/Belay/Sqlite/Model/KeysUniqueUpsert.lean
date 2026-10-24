import Belay.Sqlite.Model.DatabaseConstraintChecks
import Belay.Sqlite.Model.KeysUniqueFrame
import Belay.Sqlite.Model.StatementStep

set_option doc.verso true

/-! The theorem of the atom "keys unique" (ADR 0022, D3, slice 2) for an INSERT with
{lit}`ON CONFLICT` clauses or a conflict algorithm (upsert) without the row engine: INSERT OR
IGNORE, OR REPLACE, ON CONFLICT DO NOTHING and DO UPDATE. Each row either keeps the table or
stores a table that passed {lit}`LiteralData.checkedRow`, so every table that the rows reach
keeps the atom, also the table before a failed row, which a FAIL failure keeps. -/

namespace Belay.Sqlite.Model
namespace LiteralData

/-- For every table, algorithm, result table and row: if {name}`failedConstraint` succeeds, its
table is the table: IGNORE skips the row. Proof sketch: case analysis on the algorithm. -/
theorem failedConstraint_ok {table next : Table} {algorithm : ConflictAlgorithm} {written : Option Row}
    (ok : failedConstraint table algorithm = .ok (next, written)) : next = table := by
  cases algorithm <;> simp_all [failedConstraint]

/-- For every keys, two tables and rows: if {name}`checkedRow` of the next table succeeds with a
table, that table satisfies {name}`Table.KeysUnique` for the keys. Proof sketch: the stored table
passed {name}`constraints`, and {name}`Table.constraints_iff` gives the atom. -/
theorem checkedRow_keysUnique {keys : List UniqueKey} {next stored : Table} {written : Row} {row : Option Row}
    (ok : checkedRow keys next written = .ok (stored, row)) : stored.KeysUnique keys := by
  unfold checkedRow at ok
  split at ok
  · rename_i passed
    simp only [Except.ok.injEq, Prod.mk.injEq] at ok
    rw [← ok.1]
    exact ((Table.constraints_iff keys next).mp (Bool.and_eq_true _ _ ▸ passed).1).2.2.2
  · simp at ok

/-- For every keys, algorithms, two tables, proposed row and row: if {name}`insertChecked`
succeeds with a table, that table is the input table or satisfies {name}`Table.KeysUnique` for
the keys. Proof sketch: a blocking key fails or keeps the table ({name}`failedConstraint_ok`),
and otherwise {name}`checkedRow_keysUnique`. -/
theorem insertChecked_ok {keys : List UniqueKey} {algorithms : List ConflictAlgorithm} {table next : Table}
    {proposed : Row} {written : Option Row} (ok : insertChecked keys algorithms table proposed = .ok (next, written)) :
    next = table ∨ next.KeysUnique keys := by
  unfold insertChecked at ok
  split at ok
  · exact .inl (failedConstraint_ok ok)
  · exact .inr (checkedRow_keysUnique ok)

/-- For every context, keys, table, assignments, filter, two rows, result table and row: if
{name}`updateExisting` succeeds with a table, that table is the input table or satisfies
{name}`Table.KeysUnique` for the keys. Proof sketch: a filter that is not true keeps the
table, a refused rowid alias fails, and otherwise {name}`checkedRow_keysUnique`. -/
theorem updateExisting_ok {context : Resolved.EvalContext} {keys : List UniqueKey} {table next : Table}
    {assignments : List (Nat × Resolved.Expr)} {filter : Option Resolved.Expr} {existing proposed : Row}
    {written : Option Row} (ok : updateExisting context keys table assignments filter existing proposed = .ok (next, written)) :
    next = table ∨ next.KeysUnique keys := by
  unfold updateExisting at ok
  dsimp only at ok
  split at ok
  · simp only [Except.ok.injEq, Prod.mk.injEq] at ok
    exact .inl ok.1.symm
  · split at ok
    · simp at ok
    · exact .inr (checkedRow_keysUnique ok)

/-- For every context, keys, policy, clauses, table, values, result table and row: if
{name}`upsertRow` succeeds with a table, that table is the input table or satisfies
{name}`Table.KeysUnique` for the keys. Proof sketch: each branch fails, keeps the table
({name}`failedConstraint_ok`, DO NOTHING, a DO UPDATE whose filter is not true), or stores a
table that {name}`checkedRow` passed ({name}`insertChecked_ok`, {name}`updateExisting_ok`). -/
theorem upsertRow_ok {context : Resolved.EvalContext} {keys : List UniqueKey} {policy : Resolved.ConflictPolicy}
    {clauses : List Resolved.ConflictClause} {table next : Table} {values : List Value} {written : Option Row}
    (ok : upsertRow context keys policy clauses table values = .ok (next, written)) : next = table ∨ next.KeysUnique keys := by
  unfold upsertRow at ok
  split at ok
  · simp at ok
  · dsimp only at ok
    split at ok
    · exact .inl (failedConstraint_ok ok)
    · split at ok
      · exact .inl (failedConstraint_ok ok)
      · split at ok
        · exact .inl (failedConstraint_ok ok)
        · split at ok
          · exact insertChecked_ok ok
          · split at ok
            · simp only [Except.ok.injEq, Prod.mk.injEq] at ok
              exact .inl ok.1.symm
            · exact updateExisting_ok ok

/-- For every context, keys, policy, clauses, table and rows: if the table satisfies
{name}`Table.KeysUnique` for the keys, the table of the result of the rows
({name}`upsertSummary` of {name}`upsertSteps`) satisfies it too: the final table when the rows
succeed, and the table before the failed row when a row fails. Proof sketch: induction on the
rows; each row keeps the table or stores one that satisfies the atom ({name}`upsertRow_ok`). -/
theorem upsertSummary_keysUnique (context : Resolved.EvalContext) (keys : List UniqueKey)
    (policy : Resolved.ConflictPolicy) (clauses : List Resolved.ConflictClause) :
    ∀ (rows : List (List Value)) {table : Table}, table.KeysUnique keys →
      match upsertSummary table (upsertSteps context keys policy clauses table rows) with
      | .ok (final, _) => final.KeysUnique keys
      | .error (_, reached, _) => reached.KeysUnique keys
  | [], _, unique => unique
  | values :: rest, table, unique => by
    simp only [upsertSteps, upsertSummary]
    cases result : upsertRow context keys policy clauses table values with
    | error reason => exact unique
    | ok pair =>
      obtain ⟨next, written⟩ := pair
      have kept : next.KeysUnique keys := by
        rcases upsertRow_ok result with same | stored
        · exact same ▸ unique
        · exact stored
      have later := upsertSummary_keysUnique context keys policy clauses rest kept
      dsimp only
      rcases summary : upsertSummary next (upsertSteps context keys policy clauses next rest) with
        ⟨_, _, _⟩ | ⟨_, _⟩ <;> simp only [summary] at later ⊢ <;> exact later

end LiteralData

/-- For every clock value, counters, parameter list, INSERT with {lit}`ON CONFLICT` clauses or a conflict
algorithm without foreign key rules and trigger programs ({lean}`(none : Option Resolved.WriteRules)`),
and database: if the database satisfies {name}`Database.KeysUnique`, the database of the effect of
{name}`runStatement` satisfies it too, on success and on every error, which is more than
{name}`Effect.KeysUnique` asks. It assumes nothing about the support check. Proof sketch: the
statement stores the table of {name}`LiteralData.upsertSummary` at the target, which satisfies
the atom ({name}`LiteralData.upsertSummary_keysUnique`), with {name}`Database.KeysUnique.setRows`. -/
theorem runStatement_upsert_keysUnique (clock : Int) (counters : Counters) (parameters : List Value) (target : Nat)
    (rows : List (List Resolved.Cell)) (clauses : List Resolved.ConflictClause) (returning : List (Resolved.Expr × String))
    (algorithm : Option ConflictAlgorithm) (subqueries : List Resolved.Query) {database : Database}
    (unique : database.KeysUnique) :
    (effectDatabase (runStatement clock counters parameters
      (.upsert target rows clauses returning algorithm subqueries none) database).effect).KeysUnique := by
  simp only [runStatement, Option.map_none, StatementRun.withKeys]
  split
  · exact unique
  · rename_i table found
    have summary := LiteralData.upsertSummary_keysUnique (Resolved.statementContext clock counters parameters database subqueries)
      (database.keys target table) (database.catalog.writePolicy target table.shape algorithm) clauses
      (Resolved.rowsAt (Resolved.statementContext clock counters parameters database subqueries) table.shape.columns rows)
      (unique target table found)
    dsimp only
    split
    · rename_i final written result
      rw [result] at summary
      exact unique.setRows found (summary.frame rfl fun _ member => member)
    · rename_i reason reached written result
      rw [result] at summary
      exact unique.setRows found (summary.frame rfl fun _ member => member)

end Belay.Sqlite.Model
