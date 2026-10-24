import Belay.Sqlite.Model.AdmittedUpsertSummary
import Belay.Sqlite.Model.AdmittedWriteReady

set_option doc.verso true

/-! The upsert statement and the table atoms of {lit}`Database.Admitted` (ADR 0022, D3, slice 4). An
INSERT with {lit}`ON CONFLICT` clauses or conflict algorithms, without foreign key rules and trigger
programs, stores the table that its last reached row left, or the table before the failed row. So an atom
holds in the database of the effect when it holds for that table. {lit}`runStatement_upsert_atom` says
this for any atom, and {lit}`runStatement_upsert_atom_of_steps` reads the table from the rows with a
step law, so the theorem of each atom only gives the law for one row. -/

namespace Belay.Sqlite.Model

/-- For every atom, clock value, counters, parameter list, upsert without rules and database: if every
table of the database has the atom, and for the table at the target the table of the result of the rows
has the entry of the table and the atom, then every table of the database of the effect of
{name}`runStatement` has the atom, on success and on every error, which is more than
{name}`Effect.Satisfies` asks. Proof sketch: the statement stores the table of
{name}`LiteralData.upsertSummary` at the target, with {name}`Database.EachTable.setRows`. -/
theorem runStatement_upsert_atom {atom : Table → Prop} (clock : Int) (counters : Counters)
    (parameters : List Value) (target : Nat) (rows : List (List Resolved.Cell))
    (clauses : List Resolved.ConflictClause) (returning : List (Resolved.Expr × String))
    (algorithm : Option ConflictAlgorithm) (subqueries : List Resolved.Query) {database : Database}
    (every : database.EachTable atom)
    (summary : ∀ table, database.table target = some table →
      match LiteralData.upsertSummary table (LiteralData.upsertSteps
          (Resolved.statementContext clock counters parameters database subqueries) (database.keys target table)
          (database.catalog.writePolicy target table.shape algorithm) clauses table
          (Resolved.rowsAt (Resolved.statementContext clock counters parameters database subqueries)
            table.shape.columns rows)) with
      | .ok (final, _) => final.shape = table.shape ∧ atom final
      | .error (_, reached, _) => reached.shape = table.shape ∧ atom reached) :
    (effectDatabase (runStatement clock counters parameters
      (.upsert target rows clauses returning algorithm subqueries none) database).effect).EachTable atom := by
  simp only [runStatement, Option.map_none, StatementRun.withKeys]
  split
  · exact every
  · rename_i table found
    have result := summary table found
    dsimp only
    split
    · rename_i final written run
      rw [run] at result
      obtain ⟨shape, holds⟩ := result
      cases final
      subst shape
      exact every.setRows found holds
    · rename_i reason reached written run
      rw [run] at result
      obtain ⟨shape, holds⟩ := result
      cases reached
      subst shape
      exact every.setRows found holds

/-- For every atom, clock value, counters, parameter list, upsert without rules and database: if every
table of the database has the atom, the queue test ({lit}`queued`) holds for the supplied rows over the table
at the target, and the step law holds, then the effect of {name}`runStatement` satisfies "every table has
the atom" ({name}`Effect.Satisfies`). The step law says: for the table at the target, a table with the
same entry, the atom and the queue test, and a row that {name}`LiteralData.upsertRow` runs to a next table,
the next table has the atom and the queue test for the rest of the queue. Proof sketch:
{name}`runStatement_upsert_atom` with {name}`LiteralData.upsertSummary_atom`, where the atom also keeps
the entry of the table. -/
theorem runStatement_upsert_satisfies_of_steps {atom : Table → Prop} (clock : Int) (counters : Counters)
    (parameters : List Value) (target : Nat) (rows : List (List Resolved.Cell))
    (clauses : List Resolved.ConflictClause) (returning : List (Resolved.Expr × String))
    (algorithm : Option ConflictAlgorithm) (subqueries : List Resolved.Query) {database : Database}
    (every : database.EachTable atom) (queued : Table → List (List Value) → Table → Prop)
    (start : ∀ table, database.table target = some table →
      queued table (Resolved.rowsAt (Resolved.statementContext clock counters parameters database subqueries)
        table.shape.columns rows) table)
    (step : ∀ table, database.table target = some table → ∀ (current next : Table) (values : List Value)
      (rest : List (List Value)) (written : Option Row), current.shape = table.shape → atom current →
      queued table (values :: rest) current →
      LiteralData.upsertRow (Resolved.statementContext clock counters parameters database subqueries)
        (database.keys target table) (database.catalog.writePolicy target table.shape algorithm) clauses current
        values = .ok (next, written) → atom next ∧ queued table rest next) :
    (runStatement clock counters parameters
      (.upsert target rows clauses returning algorithm subqueries none) database).effect.Satisfies
      fun after => after.EachTable atom := by
  refine Effect.satisfies_of_effectDatabase (runStatement_upsert_atom clock counters parameters target rows clauses
    returning algorithm subqueries every fun table found => ?_)
  have result := LiteralData.upsertSummary_atom (atom := fun current => current.shape = table.shape ∧ atom current)
    (Resolved.statementContext clock counters parameters database subqueries) (database.keys target table)
    (database.catalog.writePolicy target table.shape algorithm) clauses (queued table)
    (fun current next values rest written good ahead run =>
      have kept := step table found current next values rest written good.1 good.2 ahead run
      ⟨LiteralData.upsertRow_shape run, ⟨(LiteralData.upsertRow_shape run).trans good.1, kept.1⟩, kept.2⟩)
    _ table ⟨rfl, every _ table found⟩ (start table found)
  rcases summary : LiteralData.upsertSummary table (LiteralData.upsertSteps
      (Resolved.statementContext clock counters parameters database subqueries) (database.keys target table)
      (database.catalog.writePolicy target table.shape algorithm) clauses table
      (Resolved.rowsAt (Resolved.statementContext clock counters parameters database subqueries)
        table.shape.columns rows)) with ⟨_, _, _⟩ | ⟨_, _⟩ <;>
    simp only [summary] at result ⊢ <;> exact ⟨result.1, result.2.2⟩

end Belay.Sqlite.Model
