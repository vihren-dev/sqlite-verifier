import Belay

/-! Scalar function calls without FROM use the same query observations as non-call scalars.
The free-database proofs retain function faults; kernel instances check both sides of each law. -/

open Belay.Sqlite
open Belay.Sqlite.Model hiding Database

/-- A closed ABS expression is quiet, even when its integer argument makes ABS fail. -/
theorem quiet_abs (value : Int) :
    (Resolved.Expr.scalar .abs (.cons (.literal (.integer value)) .nil)).Quiet :=
  ⟨rfl, fun _ => rfl⟩

/-- A scalar function call with a fitting argument has a row on every database. -/
theorem scalar_abs_holds (db : Database) : Holds (sql r"SELECT abs(1)") db := by
  have resolved := resolveStatement_selectNoFrom_columns runContext db.raw.connection.resolveState
    (.call "abs" [.numeric "1"]) "abs(1)" "abs(1)" none
    (.scalar .abs (.cons (.literal (.integer 1)) .nil)) none none
    (by decide +kernel) (by decide +kernel) (by decide +kernel) (FilterResolves.of_none _ _ _ _)
  exact (Holds.iff_noFrom_scalar (head := rfl) resolved
    (Resolved.Statement.Quiet.selectNoFrom _ _ _ (by simp) (quiet_abs 1))).2 (by decide +kernel)

/-- A known ABS overflow is a failure on every database. -/
theorem scalar_abs_fails (db : Database) : Fails (sql r"SELECT abs(-9223372036854775808)") db := by
  have resolved := resolveStatement_selectNoFrom_columns runContext db.raw.connection.resolveState
    (.call "abs" [.negate (.numeric "9223372036854775808")])
    "abs(-9223372036854775808)" "abs(-9223372036854775808)" none
    (.scalar .abs (.cons (.literal (.integer (-9223372036854775808))) .nil)) none none
    (by decide +kernel) (by decide +kernel) (by decide +kernel) (FilterResolves.of_none _ _ _ _)
  exact (Fails.iff_noFrom_scalar (head := rfl) resolved
    (Resolved.Statement.Quiet.selectNoFrom _ _ _ (by simp) (quiet_abs _))).2 (by decide +kernel)

/-- A false filter skips even a failing scalar projection on every database. -/
theorem scalar_abs_skipped (db : Database) : Empty (sql r"SELECT abs(-9223372036854775808) WHERE 0") db := by
  have resolved := resolveStatement_selectNoFrom_columns runContext db.raw.connection.resolveState
    (.call "abs" [.negate (.numeric "9223372036854775808")])
    "abs(-9223372036854775808)" "abs(-9223372036854775808)" (some (.numeric "0"))
    (.scalar .abs (.cons (.literal (.integer (-9223372036854775808))) .nil)) none (some (.literal (.integer 0)))
    (by decide +kernel) (by decide +kernel) (by decide +kernel)
    (FilterResolves.of_term (result := (.literal (.integer 0), none)) (by decide +kernel) (by decide +kernel))
  refine (Empty.iff_noFrom_scalar (head := rfl) resolved
    (Resolved.Statement.Quiet.selectNoFrom _ _ _ ?_ (quiet_abs _))).2 (by decide +kernel)
  intro part member
  simp only [Option.toList, List.mem_singleton] at member
  subst member
  exact (Resolved.Expr.calm_literal _).quiet

/-- An arbitrary nonempty schema witnesses the free-database results. -/
def blank : Database := db! r"CREATE TABLE t (x INTEGER);"

example : Holds (sql r"SELECT abs(1)") blank := scalar_abs_holds blank
example : Fails (sql r"SELECT abs(-9223372036854775808)") blank := scalar_abs_fails blank
example : Empty (sql r"SELECT abs(-9223372036854775808) WHERE 0") blank := scalar_abs_skipped blank
example : Holds (sql r"SELECT abs(1)") blank := by decide +kernel
example : ¬ Empty (sql r"SELECT abs(1)") blank := by decide +kernel
example : ¬ Fails (sql r"SELECT abs(1)") blank := by decide +kernel
example : Fails (sql r"SELECT abs(-9223372036854775808)") blank := by decide +kernel
example : ¬ Holds (sql r"SELECT abs(-9223372036854775808)") blank := by decide +kernel
example : ¬ Empty (sql r"SELECT abs(-9223372036854775808)") blank := by decide +kernel
example : Empty (sql r"SELECT abs(-9223372036854775808) WHERE 0") blank := by decide +kernel
example : ¬ Holds (sql r"SELECT abs(-9223372036854775808) WHERE 0") blank := by decide +kernel
example : ¬ Fails (sql r"SELECT abs(-9223372036854775808) WHERE 0") blank := by decide +kernel

#print axioms Holds.iff_noFrom_scalar
#print axioms Empty.iff_noFrom_scalar
#print axioms Fails.iff_noFrom_scalar
