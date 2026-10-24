import Belay

/-! A fixture of `tests/surface_claims_test.py`: the query form `SELECT 1 WHERE NOT EXISTS (SELECT 1 FROM t GROUP BY k
HAVING count(*) > 1)` over every database (ADR 0017, S4; `Belay/Sqlite/DuplicateKeyQuery.lean`). Each claim is about
every database; each claim has instances on databases, where `decide +kernel` checks that its two sides agree, so that
no claim is vacuous. The instances include a column with the collation `NOCASE` (two keys that differ only in case are
one group) and two NULL keys (NULL keys are one group, unlike a `UNIQUE` index). -/

open Belay.Sqlite
open Belay.Sqlite.Model hiding Database

/-- A table `users` whose `email` has the collation `NOCASE`, with three different addresses. -/
def distinctUsers : Database := db! r"
  CREATE TABLE users (id INTEGER PRIMARY KEY, email TEXT COLLATE NOCASE);
  INSERT INTO users (id, email) VALUES (1, 'a@x.org'), (2, 'b@x.org'), (3, 'c@x.org');"

/-- The same table, where the addresses of rows 1 and 2 differ only in case. -/
def caseUsers : Database := db! r"
  CREATE TABLE users (id INTEGER PRIMARY KEY, email TEXT COLLATE NOCASE);
  INSERT INTO users (id, email) VALUES (1, 'a@x.org'), (2, 'A@X.ORG'), (3, 'c@x.org');"

/-- The same table, where rows 1 and 2 have no address. -/
def nullUsers : Database := db! r"
  CREATE TABLE users (id INTEGER PRIMARY KEY, email TEXT COLLATE NOCASE);
  INSERT INTO users (id, email) VALUES (1, NULL), (2, NULL), (3, 'c@x.org');"

/-- The catalog position and the table of `users` in `distinctUsers`. -/
def distinctTable : Nat × CatalogTable :=
  (distinctUsers.raw.catalog.findTable (name! "users")).get (by decide +kernel)

/-- The catalog position and the table of `users` in `caseUsers`. -/
def caseTable : Nat × CatalogTable := (caseUsers.raw.catalog.findTable (name! "users")).get (by decide +kernel)

/-- The catalog position and the table of `users` in `nullUsers`. -/
def nullTable : Nat × CatalogTable := (nullUsers.raw.catalog.findTable (name! "users")).get (by decide +kernel)

example : distinctUsers.raw.catalog.findTable (name! "users") = some distinctTable := by decide +kernel
example : caseUsers.raw.catalog.findTable (name! "users") = some caseTable := by decide +kernel
example : nullUsers.raw.catalog.findTable (name! "users") = some nullTable := by decide +kernel

/-- The groups that the query makes of the rows of `users`: grouped by `email` (the cell `index`) under the collation of
that column. -/
abbrev emailGroups (db : Database) (position index : Nat) (table : CatalogTable) : List (List (List Value)) :=
  Resolved.groups (Resolved.EvalContext.bound []) [(.column index, (table.columns[index]?.map (·.collation)).getD .binary)]
    (Resolved.sourceRows { shape := table, rows := db.raw.rows.getD position [] })

/-- Over every database that has a table `users` with a column `email` at position `index`, "no two users have the
same email" is a claim about the groups of rows with equal emails, as `GROUP BY` makes them: the query holds exactly
when no group has more than one row. Proof sketch: the group key resolves to the cell with the collation of the
column (`GroupTermResolves.identifier_table`), and `Holds.iff_selectOne_noDuplicateKeys` turns the claim into the
statement about the groups. -/
theorem every_email_is_unique (db : Database) (position index : Nat) (table : CatalogTable)
    (found : db.raw.catalog.findTable (name! "users") = some (position, table))
    (column : columnPosition table.columns (name! "email") = some index) :
    Holds (sql r"SELECT 1 WHERE NOT EXISTS (SELECT 1 FROM users GROUP BY email HAVING count(*) > 1)") db ↔
      ∀ group ∈ emailGroups db position index table, group.length ≤ 1 :=
  Holds.iff_selectOne_noDuplicateKeys (namedSource := rfl) (head := rfl) (reference := { table := name! "users", alias := none }) (by decide) rfl found
    (GroupTermResolves.identifier_table column) (Resolved.Expr.calm_column index)

/-- Over every database as in `every_email_is_unique`, the query is empty exactly when some group has more than one
row, which is some pair of users with an equal email (two NULL emails are equal for `GROUP BY`). -/
theorem some_email_is_repeated (db : Database) (position index : Nat) (table : CatalogTable)
    (found : db.raw.catalog.findTable (name! "users") = some (position, table))
    (column : columnPosition table.columns (name! "email") = some index) :
    Empty (sql r"SELECT 1 WHERE NOT EXISTS (SELECT 1 FROM users GROUP BY email HAVING count(*) > 1)") db ↔
      ∃ group ∈ emailGroups db position index table, 1 < group.length :=
  Empty.iff_selectOne_noDuplicateKeys (namedSource := rfl) (head := rfl) (reference := { table := name! "users", alias := none }) (by decide) rfl found
    (GroupTermResolves.identifier_table column) (Resolved.Expr.calm_column index)

/-- Over every database as in `every_email_is_unique`, the query does not fail. -/
theorem email_check_does_not_fail (db : Database) (position index : Nat) (table : CatalogTable)
    (found : db.raw.catalog.findTable (name! "users") = some (position, table))
    (column : columnPosition table.columns (name! "email") = some index) :
    ¬ Fails (sql r"SELECT 1 WHERE NOT EXISTS (SELECT 1 FROM users GROUP BY email HAVING count(*) > 1)") db :=
  Fails.not_selectOne_noDuplicateKeys (namedSource := rfl) (head := rfl) (reference := { table := name! "users", alias := none }) (by decide) rfl found
    (GroupTermResolves.identifier_table column) (Resolved.Expr.calm_column index)

/-- The guide's claim, over every database that has a table `users` with a column `email` at position `index`: the query
holds exactly when no user has an email that compares as equal, under the collation of the column, to the email of a
user before it in scan order. Two users with NULL emails compare as equal here, unlike under a `UNIQUE` index. Proof
sketch: `Holds.iff_selectOne_noDuplicateKeys_pairwise`, and the key `.column index` reads the cell `index`. -/
theorem no_two_users_share_an_email (db : Database) (position index : Nat) (table : CatalogTable)
    (found : db.raw.catalog.findTable (name! "users") = some (position, table))
    (column : columnPosition table.columns (name! "email") = some index) :
    Holds (sql r"SELECT 1 WHERE NOT EXISTS (SELECT 1 FROM users GROUP BY email HAVING count(*) > 1)") db ↔
      (Resolved.sourceRows { shape := table, rows := db.raw.rows.getD position [] }).Pairwise
        fun (earlier later : List Value) => ((table.columns[index]?.map CatalogColumn.collation).getD .binary).compare
          (later.getD index .null) (earlier.getD index .null) ≠ Ordering.eq := by
  refine Iff.trans (Holds.iff_selectOne_noDuplicateKeys_pairwise (namedSource := rfl) (head := rfl) (reference := { table := name! "users", alias := none })
    (by decide) rfl found (GroupTermResolves.identifier_table column) (Resolved.Expr.calm_column index)) ?_
  simp [Resolved.Expr.eval_column]

/-- Over every database as in `no_two_users_share_an_email`, the query is empty exactly when some user has an email that
compares as equal to the email of a user before it. Proof sketch: as for `no_two_users_share_an_email`, with
`Empty.iff_selectOne_noDuplicateKeys_repeated`. -/
theorem two_users_share_an_email (db : Database) (position index : Nat) (table : CatalogTable)
    (found : db.raw.catalog.findTable (name! "users") = some (position, table))
    (column : columnPosition table.columns (name! "email") = some index) :
    Empty (sql r"SELECT 1 WHERE NOT EXISTS (SELECT 1 FROM users GROUP BY email HAVING count(*) > 1)") db ↔
      ¬ (Resolved.sourceRows { shape := table, rows := db.raw.rows.getD position [] }).Pairwise
        fun (earlier later : List Value) => ((table.columns[index]?.map CatalogColumn.collation).getD .binary).compare
          (later.getD index .null) (earlier.getD index .null) ≠ Ordering.eq := by
  refine Iff.trans (Empty.iff_selectOne_noDuplicateKeys_repeated (namedSource := rfl) (head := rfl) (reference := { table := name! "users", alias := none })
    (by decide) rfl found (GroupTermResolves.identifier_table column) (Resolved.Expr.calm_column index)) ?_
  simp [Resolved.Expr.eval_column]

-- The instance with addresses that differ only in case, in the pairwise form: both sides agree.
example : Empty (sql r"SELECT 1 WHERE NOT EXISTS (SELECT 1 FROM users GROUP BY email HAVING count(*) > 1)") caseUsers :=
  (two_users_share_an_email caseUsers caseTable.1 1 caseTable.2 (by decide +kernel)
    (by decide +kernel)).2 (by decide +kernel)

-- The instance with three different addresses, in the pairwise form: both sides agree.
example : Holds (sql r"SELECT 1 WHERE NOT EXISTS (SELECT 1 FROM users GROUP BY email HAVING count(*) > 1)") distinctUsers :=
  (no_two_users_share_an_email distinctUsers distinctTable.1 1 distinctTable.2 (by decide +kernel)
    (by decide +kernel)).2 (by decide +kernel)

-- The instance with three different addresses: the query holds, and no group has two rows.
example : Holds (sql r"SELECT 1 WHERE NOT EXISTS (SELECT 1 FROM users GROUP BY email HAVING count(*) > 1)") distinctUsers :=
  (every_email_is_unique distinctUsers distinctTable.1 1 distinctTable.2 (by decide +kernel)
    (by decide +kernel)).2 (by decide +kernel)

-- The instance with addresses that differ only in case: `NOCASE` puts them in one group, so the query is empty.
example : Empty (sql r"SELECT 1 WHERE NOT EXISTS (SELECT 1 FROM users GROUP BY email HAVING count(*) > 1)") caseUsers :=
  (some_email_is_repeated caseUsers caseTable.1 1 caseTable.2 (by decide +kernel)
    (by decide +kernel)).2 (by decide +kernel)

-- The instance with two NULL addresses: they are one group, so the query is empty.
example : Empty (sql r"SELECT 1 WHERE NOT EXISTS (SELECT 1 FROM users GROUP BY email HAVING count(*) > 1)") nullUsers :=
  (some_email_is_repeated nullUsers nullTable.1 1 nullTable.2 (by decide +kernel)
    (by decide +kernel)).2 (by decide +kernel)

-- Both sides agree on the instance with a repeated address: the query does not hold.
example : ¬ Holds (sql r"SELECT 1 WHERE NOT EXISTS (SELECT 1 FROM users GROUP BY email HAVING count(*) > 1)") caseUsers :=
  fun holds => absurd ((every_email_is_unique caseUsers caseTable.1 1 caseTable.2 (by decide +kernel)
    (by decide +kernel)).1 holds) (by decide +kernel)

-- The group-based Empty equivalence also has a false instance, with distinct keys on both sides.
example : ¬ Empty (sql r"SELECT 1 WHERE NOT EXISTS (SELECT 1 FROM users GROUP BY email HAVING count(*) > 1)") distinctUsers := by
  rw [some_email_is_repeated distinctUsers distinctTable.1 1 distinctTable.2 (by decide +kernel) (by decide +kernel)]
  decide +kernel

-- The pairwise Empty equivalence has the same false instance without relying on the group equivalence.
example : ¬ Empty (sql r"SELECT 1 WHERE NOT EXISTS (SELECT 1 FROM users GROUP BY email HAVING count(*) > 1)") distinctUsers := by
  rw [two_users_share_an_email distinctUsers distinctTable.1 1 distinctTable.2 (by decide +kernel) (by decide +kernel)]
  decide +kernel
example : ¬ Holds (sql r"SELECT 1 WHERE NOT EXISTS (SELECT 1 FROM users GROUP BY email HAVING count(*) > 1)") caseUsers := by
  rw [no_two_users_share_an_email caseUsers caseTable.1 1 caseTable.2 (by decide +kernel) (by decide +kernel)]
  decide +kernel

-- Duplicate keys change row existence, while both catalog-valid queries remain free of errors.
example : ¬ Fails (sql r"SELECT 1 WHERE NOT EXISTS (SELECT 1 FROM users GROUP BY email HAVING count(*) > 1)") distinctUsers :=
  email_check_does_not_fail distinctUsers distinctTable.1 1 distinctTable.2 (by decide +kernel) (by decide +kernel)
example : ¬ Fails (sql r"SELECT 1 WHERE NOT EXISTS (SELECT 1 FROM users GROUP BY email HAVING count(*) > 1)") caseUsers :=
  email_check_does_not_fail caseUsers caseTable.1 1 caseTable.2 (by decide +kernel) (by decide +kernel)
