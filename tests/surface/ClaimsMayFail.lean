import Belay

/-! A fixture of `tests/surface_claims_test.py`: a query whose `WHERE` may fail has no modeled output
(ADR 0017, S4; `Belay/Sqlite/SelectOneMayFail.lean`). `abs` fails on the smallest 64-bit integer, so
`SELECT 1 FROM t WHERE abs(x) = 1` on a table with the rows `-9223372036854775808` and `1` returns a row
and then fails in SQLite (measured 2026-10-24); the model gives the output `Output.unmodeled`, and none
of `Holds`, `Empty` and `Fails` holds. The same query on a table without that row holds. -/

open Belay.Sqlite
open Belay.Sqlite.Model hiding Database

/-- A table `t` with the smallest 64-bit integer and the integer 1. -/
def numbers : Database := db! r"
  CREATE TABLE t (x INTEGER);
  INSERT INTO t (x) VALUES (-9223372036854775808), (1);"

/-- A table `t` without that integer, where `abs(x) = 1` is true for the row 1. -/
def smaller : Database := db! r"
  CREATE TABLE t (x INTEGER);
  INSERT INTO t (x) VALUES (-5), (1);"

/-- The query `SELECT 1 FROM t WHERE abs(x) = 1`. -/
def absScript : Script := sql r"SELECT 1 FROM t WHERE abs(x) = 1"

example : ¬ Holds absScript numbers := by decide +kernel
example : ¬ Empty absScript numbers := by decide +kernel
example : ¬ Fails absScript numbers := by decide +kernel
example : Holds absScript smaller := by decide +kernel

/-- The catalog position and the table of `t` in `numbers`. -/
def numbersTable : Nat × CatalogTable := (numbers.raw.catalog.findTable (name! "t")).get (by decide +kernel)

/-- The lemma gives the same three facts for the database `numbers`, from the call that may fail on the first row
(`Script.not_claims_selectOne_of_mayFail`). Its hypotheses hold: the condition resolves, reads no clock
and no counter, and `abs` may fail on the row. -/
example : ¬ Holds absScript numbers ∧ ¬ Empty absScript numbers ∧ ¬ Fails absScript numbers :=
  Script.not_claims_selectOne_of_mayFail (db := numbers) (isQuery := rfl) (position := numbersTable.1)
    (table := numbersTable.2)
    (condition := some (.compare .eq none (.scalar .abs (.cons (.column 0) .nil)) (.literal (.integer 1)) .binary))
    (head := rfl) (arguments := rfl) (found := by decide +kernel)
    (FilterResolves.of_term (shapes := { later := [] })
      (result := (.compare .eq none (.scalar .abs (.cons (.column 0) .nil)) (.literal (.integer 1)) .binary, none))
      (by decide +kernel) (by decide +kernel))
    (fun e member => by
      simp only [Option.toList, List.mem_singleton] at member
      subst member
      exact ⟨by decide +kernel, fun kind => by cases kind <;> decide +kernel⟩)
    (row := [.integer (-9223372036854775808)]) (by decide +kernel)
    (expression := .compare .eq none (.scalar .abs (.cons (.column 0) .nil)) (.literal (.integer 1)) .binary)
    (by decide +kernel) (by decide +kernel)

/-- The query `SELECT 1 WHERE EXISTS (SELECT 1 FROM t WHERE abs(x) = 1)`. SQLite may evaluate a subquery for rows that the
model does not reach, so the model does not describe a call that can fail in a subquery: for every table, the output is
`Output.unmodeled`, also for `smaller`, where `abs` cannot fail. -/
def absExists : Script := sql r"SELECT 1 WHERE EXISTS (SELECT 1 FROM t WHERE abs(x) = 1)"

example : ¬ Holds absExists numbers ∧ ¬ Empty absExists numbers ∧ ¬ Fails absExists numbers := by
  refine ⟨?_, ?_, ?_⟩ <;> decide +kernel

example : ¬ Holds absExists smaller := by decide +kernel

/-- The lemma gives the three facts for `absExists` on `numbers` and on every other database: the call of `abs` in the
subquery makes the subquery not plain (`Script.not_claims_selectOne_exists_of_fallible`). -/
example : ¬ Holds absExists numbers ∧ ¬ Empty absExists numbers ∧ ¬ Fails absExists numbers :=
  Script.not_claims_selectOne_exists_of_fallible (db := numbers) (isQuery := rfl) (position := numbersTable.1)
    (table := numbersTable.2)
    (subCondition := some (.compare .eq none (.scalar .abs (.cons (.column 0) .nil)) (.literal (.integer 1)) .binary))
    (head := rfl) (arguments := rfl) (found := by decide +kernel)
    (FilterResolves.of_term (shapes := { current := some 0 })
      (result := (.compare .eq none (.scalar .abs (.cons (.column 0) .nil)) (.literal (.integer 1)) .binary, none))
      (by decide +kernel) (by decide +kernel))
    (fun e member => by
      simp only [Option.toList, List.mem_singleton] at member
      subst member
      exact ⟨by decide +kernel, fun kind => by cases kind <;> decide +kernel⟩)
    (expression := .compare .eq none (.scalar .abs (.cons (.column 0) .nil)) (.literal (.integer 1)) .binary)
    (by decide +kernel) (by decide +kernel)
