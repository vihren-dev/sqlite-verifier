import Belay

/-! Shared error and unmodeled laws for all query forms. The free-database theorem uses the
prepare-error contract; kernel examples cover missing tables and columns in each form.
The axiom output checks the bridge and unique-lookup public theorem. -/

open Belay.Sqlite
open Belay.Sqlite.Model hiding Database

/-- Every query whose resolver reports a prepare error fails, including errors in nested queries.
Proof sketch: the shared prepare-error law gives the failure; errors exclude the other claims. -/
theorem prepare_error_has_no_rows {script : Script} {db : Database} {isQuery : script.isQuery = true}
    {statement : Syntax.Statement} {parameters : List Value} {rest : List (Syntax.Statement × List Value)}
    {error : PrepareError} {after : ResolveState}
    (head : script.statements = (statement, parameters) :: rest)
    (resolved : resolveStatement runContext db.raw.connection.resolveState statement = .ok (.prepareError error, after)) :
    Fails script db isQuery ∧ ¬ Holds script db isQuery ∧ ¬ Empty script db isQuery := by
  have fails : Fails script db isQuery := Fails.of_prepareError head resolved
  exact ⟨fails, fun holds => holds.not_fails fails, fun empty => empty.not_fails fails⟩

/-- A SELECT without FROM that names an unknown column fails over every database.
Proof sketch: its sources and star check are empty, and the column resolver reports a prepare error. -/
theorem unknown_column_fails (db : Database) : Fails (sql r"SELECT missing") db := by
  let query : Syntax.Subquery := ⟨[.expression (.identifier (name! "missing") .none) none "missing"],
    none, [], none, [], [], none, none, none, none, false, none⟩
  exact Fails.select_body_prepareError query [] [] (.noSuchColumn (name! "missing")) rfl rfl rfl rfl
    (resolveSources_none _) rfl (by decide +kernel)

/-- One table whose only column is `x`, for missing-column and missing-table cases. -/
def sample : Database := db! r"CREATE TABLE t (x INTEGER); INSERT INTO t VALUES (1);"

/-- Missing result columns are prepare errors for a SELECT without FROM. -/
example : Fails (sql r"SELECT missing") sample := by decide +kernel

/-- A missing table is an error for a simple table query. -/
example : Fails (sql r"SELECT 1 FROM missing WHERE x = 1") sample := by decide +kernel

/-- A missing filter column is an error even though the table exists. -/
example : Fails (sql r"SELECT 1 FROM t WHERE missing = 1") sample := by decide +kernel

/-- EXISTS retains the prepare error of its nested query. -/
example : Fails (sql r"SELECT 1 WHERE EXISTS (SELECT 1 FROM missing)") sample := by decide +kernel

/-- NOT EXISTS does not turn a missing nested column into truth. -/
example : Fails (sql r"SELECT 1 WHERE NOT EXISTS (SELECT 1 FROM t WHERE missing = 1)") sample := by decide +kernel

/-- IN retains a missing result-column error in its nested query. -/
example : Fails (sql r"SELECT 1 WHERE 1 IN (SELECT missing FROM t)") sample := by decide +kernel

/-- COUNT retains a missing nested table error. -/
example : Fails (sql r"SELECT 1 WHERE (SELECT count(*) FROM missing) <= 1") sample := by decide +kernel

/-- A duplicate-key check retains a missing grouping-column error. -/
example : Fails (sql r"SELECT 1 WHERE NOT EXISTS (SELECT 1 FROM t GROUP BY missing HAVING count(*) > 1)") sample := by
  decide +kernel

/-- SUM retains a missing operand-column error. -/
example : Fails (sql r"SELECT sum(missing) FROM t") sample := by decide +kernel

/-- Pragma result columns are resolved too; an unknown name is an error. -/
example : Fails (sql r"SELECT 1 FROM pragma_table_info('t') WHERE missing = 1") sample := by decide +kernel

/-- A known column is a negative failure instance. -/
example : ¬ Fails (sql r"SELECT 1 FROM t WHERE x = 1") sample := by decide +kernel

/-- A clock read without a clock is unmodeled, so all three observations are false. -/
example : ¬ Holds (sql r"SELECT CURRENT_TIMESTAMP") sample ∧
    ¬ Empty (sql r"SELECT CURRENT_TIMESTAMP") sample ∧ ¬ Fails (sql r"SELECT CURRENT_TIMESTAMP") sample := by
  apply Script.not_claims_of_unmodeled (reason := clockUnmodeled)
  decide +kernel

#print axioms Script.outputOn_eq_step
#print axioms Holds.iff_step
#print axioms Empty.iff_step
#print axioms Fails.iff_step
#print axioms prepare_error_has_no_rows
#print axioms Script.not_claims_query_of_undescribed
#print axioms Holds.selectOne_count_unique_lookup
