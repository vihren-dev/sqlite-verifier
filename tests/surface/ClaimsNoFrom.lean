import Belay

/-! A fixture of `tests/surface_claims_test.py`: the query form `SELECT e [WHERE c]` without `FROM` over
every database (ADR 0017, S4; `Belay/Sqlite/SelectNoFrom.lean`). Each claim is about every database; each
has an instance on one database, where `decide +kernel` checks it, so that no claim is vacuous. -/

open Belay.Sqlite
open Belay.Sqlite.Model hiding Database

/-- `SELECT 1` holds on every database. -/
theorem select_one_holds (db : Database) : Holds (sql r"SELECT 1") db := by
  have operand : resolveOperand runContext.profile.dqsDml [] { later := [] } false (.numeric "1") =
      .ok (.literal (.integer 1), none) := by simp [sql_simp]
  exact (Holds.iff_selectNoFrom (head := rfl) (notCall := rfl) (noAggregate := rfl) operand
    (FilterResolves.of_none _ _ _ _) (Resolved.Expr.calm_literal _) (by simp)).2 rfl

/-- `SELECT 1 WHERE 1 = 2` is empty on every database. -/
theorem select_where_false_empty (db : Database) : Empty (sql r"SELECT 1 WHERE 1 = 2") db := by
  have operand : resolveOperand runContext.profile.dqsDml [] { later := [] } false (.numeric "1") =
      .ok (.literal (.integer 1), none) := by simp [sql_simp]
  have resolves : FilterResolves runContext.profile.dqsDml [] [] (some (.compare .eq (.numeric "1") (.numeric "2")))
      (some (.compare .eq none (.literal (.integer 1)) (.literal (.integer 2)) .binary)) { later := [] } :=
    FilterResolves.of_term (result := (.compare .eq none (.literal (.integer 1)) (.literal (.integer 2)) .binary, none))
      (by simp [namesAlias]) (by simp [sql_simp]; rfl)
  refine (Empty.iff_selectNoFrom (head := rfl) (notCall := rfl) (noAggregate := rfl) operand resolves
    (Resolved.Expr.calm_literal _) ?_).2 ?_
  · intro part member; simp at member; subst member; simp [sql_simp]
  · simp [sql_simp]; decide +kernel

/-- A database with one empty table. -/
def blank : Database := db! r"CREATE TABLE t (x INTEGER);"

-- The instances on `blank`: `SELECT 1` holds, `SELECT 1 WHERE 1 = 2` is empty and does not hold or fail.
example : Holds (sql r"SELECT 1") blank := by decide +kernel
example : Empty (sql r"SELECT 1 WHERE 1 = 2") blank := by decide +kernel
example : ¬ Holds (sql r"SELECT 1 WHERE 1 = 2") blank := by decide +kernel
example : ¬ Fails (sql r"SELECT 1 WHERE 1 = 2") blank := by decide +kernel
