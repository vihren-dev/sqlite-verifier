import Belay

/-! A fixture of `tests/surface_claims_test.py`: the bound of a unique lookup, `SELECT 1 WHERE (SELECT count(*) FROM
t WHERE c = $v) <= 1` (ADR 0017, S4; `Belay/Sqlite/UniqueLookupQuery.lean`). The claim is about every database whose
table has the column `c` under a `UNIQUE` constraint. The instances are on databases, where `decide +kernel` checks
the claim, and the last one shows that the collation of the key matters: a `NOCASE` column with a `BINARY` unique index
can hold two rows that one value matches. -/

open Belay.Sqlite
open Belay.Sqlite.Model hiding Database

/-- Over every database that has a table `users` with a column `email` at position `col` under a `UNIQUE` constraint:
at most one user has the address `v`. -/
theorem an_email_matches_at_most_one_user (db : Database) (v : String) (position col : Nat) (table : CatalogTable)
    (found : db.raw.catalog.findTable (name! "users") = some (position, table))
    (column : columnPosition table.columns (name! "email") = some col)
    (declaredUnique : [col] ∈ table.uniqueKeys) :
    Holds (sql r"SELECT 1 WHERE (SELECT count(*) FROM users WHERE email = $v) <= 1") db := by
  obtain ⟨cell, columnAt, -⟩ := (columnPosition_eq_some_iff _ _ _).1 column
  have mainResolves : ∀ lowest, FilterResolves runContext.profile.dqsDml [] []
      (some (.compare .le (.subquery 0) (.numeric "1")))
      (some (.compare .le none (.subquery 0) (.literal (.integer 1)) .binary)) { later := [countShape lowest] } :=
    fun lowest => FilterResolves.of_term (term := .compare .le (.subquery 0) (.numeric "1"))
      (result := (.compare .le none (.subquery 0) (.literal (.integer 1)) .binary, none)) (by simp [namesAlias]) (by
      simp [sql_simp, countShape]; rfl)
  have subResolves := FilterResolves.of_term (dqs := runContext.profile.dqsDml)
    (scope := tableScope db.raw.catalog { table := name! "users", alias := none } position table) (aliases := [])
    (shapes := { current := some 0 })
    (term := .compare .eq (.identifier (name! "email") .none) (.parameter 1)) (by simp [namesAlias])
    (result := (.compare .eq (some cell.affinity) (.column col) (.parameter 1) cell.collation, none))
    (by simp [sql_simp, column, columnAt]; rfl)
  exact Holds.selectOne_count_unique_lookup (namedSource := rfl) (head := rfl) (count := by decide) (arguments := rfl) found subResolves
    mainResolves (key := UniqueKey.ofColumns table.columns [col]) (descending := false)
    (Catalog.ofColumns_mem_uniqueKeys_of_unique _ _ _ declaredUnique) columnAt rfl (by simp [UniqueKey.ofColumns, columnAt])

/-- The same bound for a `PRIMARY KEY`: over every database that has a table `users` whose primary key is the column
`id` at position `col`, at most one user has the id `v`. -/
theorem an_id_matches_at_most_one_user (db : Database) (v : Int64) (position col : Nat) (table : CatalogTable)
    (found : db.raw.catalog.findTable (name! "users") = some (position, table))
    (column : columnPosition table.columns (name! "id") = some col)
    (primary : table.primaryKey = [col]) :
    Holds (sql r"SELECT 1 WHERE (SELECT count(*) FROM users WHERE id = $v) <= 1") db := by
  obtain ⟨cell, columnAt, -⟩ := (columnPosition_eq_some_iff _ _ _).1 column
  have mainResolves : ∀ lowest, FilterResolves runContext.profile.dqsDml [] []
      (some (.compare .le (.subquery 0) (.numeric "1")))
      (some (.compare .le none (.subquery 0) (.literal (.integer 1)) .binary)) { later := [countShape lowest] } :=
    fun lowest => FilterResolves.of_term (term := .compare .le (.subquery 0) (.numeric "1"))
      (result := (.compare .le none (.subquery 0) (.literal (.integer 1)) .binary, none)) (by simp [namesAlias]) (by
      simp [sql_simp, countShape]; rfl)
  have subResolves := FilterResolves.of_term (dqs := runContext.profile.dqsDml)
    (scope := tableScope db.raw.catalog { table := name! "users", alias := none } position table) (aliases := [])
    (shapes := { current := some 0 })
    (term := .compare .eq (.identifier (name! "id") .none) (.parameter 1)) (by simp [namesAlias])
    (result := (.compare .eq (some cell.affinity) (.column col) (.parameter 1) cell.collation, none))
    (by simp [sql_simp, column, columnAt]; rfl)
  refine Holds.selectOne_count_unique_lookup (namedSource := rfl) (head := rfl) (count := by decide) (arguments := rfl) found subResolves
    mainResolves (key := UniqueKey.ofColumns table.columns table.primaryKey) (descending := false)
    (Catalog.ofColumns_mem_uniqueKeys_of_primaryKey _ _ _ (by simp [primary])) columnAt rfl ?_
  simp [UniqueKey.ofColumns, primary, columnAt]

/-- A table `users` whose `email` is `UNIQUE`, with two users. -/
def users : Database := db! r"
  CREATE TABLE users (id INTEGER PRIMARY KEY, email TEXT NOT NULL UNIQUE);
  INSERT INTO users (id, email) VALUES (1, 'a@x.org'), (2, 'b@x.org');"

/-- The primary key of `users` is the column `id` at position 0, so `an_id_matches_at_most_one_user` applies to it. -/
example : (users.raw.catalog.findTable (name! "users")).map (·.2.primaryKey) = some [0] := by decide +kernel

-- The instances on `users`: the bound holds for an address that one user has and for an address that no user has;
-- and the count itself is exact (one user has `a@x.org`, none has `c@x.org`), so the bound is not vacuous.
theorem users_bound_for_a_stored_address (v : String) (isStored : v = "a@x.org") :
    Holds (sql r"SELECT 1 WHERE (SELECT count(*) FROM users WHERE email = $v) <= 1") users := by
  subst isStored; decide +kernel

theorem users_bound_for_an_unknown_address (v : String) (isUnknown : v = "c@x.org") :
    Holds (sql r"SELECT 1 WHERE (SELECT count(*) FROM users WHERE email = $v) <= 1") users := by
  subst isUnknown; decide +kernel

theorem one_user_has_a_stored_address (v : String) (isStored : v = "a@x.org") :
    Holds (sql r"SELECT 1 WHERE (SELECT count(*) FROM users WHERE email = $v) = 1") users := by
  subst isStored; decide +kernel

theorem no_user_has_an_unknown_address (v : String) (isUnknown : v = "c@x.org") :
    Holds (sql r"SELECT 1 WHERE (SELECT count(*) FROM users WHERE email = $v) = 0") users := by
  subst isUnknown; decide +kernel

/-- A table with an `INTEGER` column `n` under `UNIQUE`: the comparison `n = $v` applies the affinity of the column to a
text, so the text `'1.0'` matches the stored integer 1. -/
def numbers : Database := db! r"
  CREATE TABLE numbers (id INTEGER PRIMARY KEY, n INTEGER UNIQUE);
  INSERT INTO numbers (id, n) VALUES (1, 1), (2, 2);"

theorem a_text_matches_the_integer_after_the_affinity (v : String) (isText : v = "1.0") :
    Holds (sql r"SELECT 1 WHERE (SELECT count(*) FROM numbers WHERE n = $v) = 1") numbers := by
  subst isText; decide +kernel

set_option doc.verso true

/-- A composite unique key permits two equal emails when the other key column differs. The lookup observes only
email, so this database shows why the bound requires exactly one key term. -/
def compositeEmails : Database := db! r"
  CREATE TABLE users (id INTEGER PRIMARY KEY, email TEXT NOT NULL, tenant INTEGER NOT NULL, UNIQUE (email, tenant));
  INSERT INTO users VALUES (1, 'a@x.org', 1), (2, 'a@x.org', 2);"

example : Holds (sql r"SELECT 1 WHERE (SELECT count(*) FROM users WHERE email = 'a@x.org') = 2") compositeEmails := by
  decide +kernel
example : ¬ Holds (sql r"SELECT 1 WHERE (SELECT count(*) FROM users WHERE email = 'a@x.org') <= 1") compositeEmails := by
  decide +kernel

/-- A partial unique key protects only active users. Equal emails outside its filter remain valid, so the lookup
bound needs an unfiltered key when its own condition does not imply the key filter. -/
def partialEmails : Database := db! r"
  CREATE TABLE users (id INTEGER PRIMARY KEY, email TEXT NOT NULL, active INTEGER NOT NULL);
  CREATE UNIQUE INDEX active_email ON users (email) WHERE active = 1;
  INSERT INTO users VALUES (1, 'a@x.org', 0), (2, 'a@x.org', 0), (3, 'b@x.org', 1);"

example : Holds (sql r"SELECT 1 WHERE (SELECT count(*) FROM users WHERE email = 'a@x.org') = 2") partialEmails := by
  decide +kernel
example : ¬ Holds (sql r"SELECT 1 WHERE (SELECT count(*) FROM users WHERE email = 'a@x.org') <= 1") partialEmails := by
  decide +kernel

/-- The collation of the key matters: a `NOCASE` column with a `BINARY` unique index holds `'a@x.org'` and `'A@X.ORG'`,
and `email = 'a@x.org'` (the collation of the column) matches both rows, so the bound fails. -/
def twoCases : Database := db! r"
  CREATE TABLE users (id INTEGER PRIMARY KEY, email TEXT COLLATE NOCASE);
  CREATE UNIQUE INDEX users_email ON users (email COLLATE BINARY);
  INSERT INTO users (id, email) VALUES (1, 'a@x.org'), (2, 'A@X.ORG');"

theorem the_bound_fails_for_a_binary_key_of_a_nocase_column (v : String) (isText : v = "a@x.org") :
    ¬ Holds (sql r"SELECT 1 WHERE (SELECT count(*) FROM users WHERE email = $v) <= 1") twoCases := by
  subst isText; decide +kernel
