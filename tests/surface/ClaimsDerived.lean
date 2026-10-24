import Belay

/-! Public SQL and database quotations for derived-table queries (ADR 0019, D5).
The predicates are checked by the kernel after SQL translation; no native result is embedded
in the library. The final checks ensure uncertain membership has no claimed outcome. -/

open Belay.Sqlite

/-- Two values with TEXT affinity and NOCASE collation. -/
def sourceRows : Database := db! r"
  CREATE TABLE t (x TEXT COLLATE NOCASE);
  INSERT INTO t VALUES ('a'), ('b');"

/-- A derived-column comparison retains the source column's collation. -/
example : Holds (sql r"SELECT 1 FROM (SELECT x FROM t) AS d WHERE d.x = 'A'") sourceRows := by decide +kernel

/-- A compound source supplies all columns to the outer query. -/
example : Holds (sql r"SELECT 1 FROM (SELECT 1 AS x, 2 AS y UNION ALL SELECT 3, 4) WHERE y = 4") sourceRows := by
  decide +kernel

/-- A derived source may read a permitted enclosing query's column. -/
example : Holds (sql r"SELECT 1 FROM t WHERE (SELECT x FROM (SELECT t.x AS x)) = 'a'") sourceRows := by
  decide +kernel

/-- LIMIT zero yields an empty derived source. -/
example : Empty (sql r"SELECT 1 FROM (SELECT x FROM t LIMIT 0)") sourceRows := by decide +kernel

/-- Referencing a sibling table inside a derived source is a prepare error. -/
example : Fails (sql r"SELECT 1 FROM t, (SELECT t.x)") sourceRows := by decide +kernel

/-- A LIMIT whose membership depends on the plan is not a successful query claim. -/
example : ¬ Holds (sql r"SELECT 1 FROM (SELECT x FROM t LIMIT 1)") sourceRows := by decide +kernel

/-- The same uncertain source is not an empty query claim. -/
example : ¬ Empty (sql r"SELECT 1 FROM (SELECT x FROM t LIMIT 1)") sourceRows := by decide +kernel

/-- The same uncertain source is not a failure claim. -/
example : ¬ Fails (sql r"SELECT 1 FROM (SELECT x FROM t LIMIT 1)") sourceRows := by decide +kernel
