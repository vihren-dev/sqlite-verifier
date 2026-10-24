import Belay

/-! A fixture of `tests/surface_claims_test.py`: the query form `SELECT 1 FROM
pragma_table_info('t') WHERE name = 'c'` over every database (ADR 0017, S4; `Belay/Sqlite/TableInfoQuery.lean`). Each claim is
about every database; each claim has an instance on one database, where `decide +kernel` checks that
its two sides agree, so that no claim is vacuous. -/

open Belay.Sqlite
open Belay.Sqlite.Model hiding Database

/-- The guide's first database: table `invoices` with two open invoices, of 10 and of 0. -/
def shop : Database := db! r"
  CREATE TABLE invoices (
    id INTEGER PRIMARY KEY,
    customer TEXT NOT NULL,
    amount INTEGER NOT NULL CHECK (amount >= 0),
    status TEXT NOT NULL DEFAULT 'open'
  );
  INSERT INTO invoices (id, customer, amount) VALUES (1, 'acme', 10), (2, 'zeta', 0);"

/-- The catalog position and the table of `invoices` in `shop`. -/
def invoices : Nat × CatalogTable := (shop.raw.catalog.findTable (name! "invoices")).get (by decide +kernel)

example : shop.raw.catalog.findTable (name! "invoices") = some invoices := by decide +kernel


/-- The claim behind the three below, for every script that is `SELECT 1 FROM pragma_table_info('t') WHERE name = 'c'`:
over every database that has a table, found by the name of the argument, and no table named like the function, the
query holds exactly when the table has a column that is not generated and whose name is the bytes `bytes`. -/
theorem table_has_a_stored_column_named {script : Script} {isQuery : script.isQuery = true} (db : Database)
    (argument bytes : List UInt8) (position : Nat) (table : CatalogTable) {parameters : List Value}
    {rest : List (Syntax.Statement × List Value)}
    (head : script.statements = (.select [.expression (.numeric "1") none "1"]
      (some ⟨name! "pragma_table_info", none, some [.string argument]⟩) []
      (some (.compare .eq (.identifier (name! "name") .none) (.string bytes))) [] [] none none [] none false none,
      parameters) :: rest)
    (found : db.raw.catalog.findTable ⟨argument⟩ = some (position, table))
    (notFunction : db.raw.catalog.findTable (name! "pragma_table_info") = none) :
    Holds script db isQuery ↔
      ∃ column ∈ table.columns, column.generated.isNone = true ∧ column.name.bytes = bytes := by
  have info := Catalog.tableInfoRows_of_findTable _ _ _ _ found
  have resolves : FilterResolves runContext.profile.dqsDml
      (tableInfoScope ⟨name! "pragma_table_info", none, some [.string argument]⟩ argument table.infoRows) []
      (some (.compare .eq (.identifier (name! "name") .none) (.string bytes)))
      (some (.compare .eq (comparisonAffinity (some .blob) none) (.column 1) (.literal (.text bytes)))) :=
    FilterResolves.of_term (result := (.compare .eq (comparisonAffinity (some .blob) none) (.column 1)
      (.literal (.text bytes)) .binary, none))
      (by simp [namesAlias]) (by simp [sql_simp])
  refine Iff.trans (Holds.iff_selectOne_tableInfo head rfl (by simp [Identifier.isKeyword, equalsKeyword]; decide +kernel) notFunction info resolves
    (by simp [sql_simp])) (Iff.trans ?_ (Iff.trans (CatalogTable.exists_pragmaRow_name table argument
      (fun cell => cell = Value.text bytes)) ?_))
  · refine exists_congr fun row => and_congr_right fun _ => ?_
    simp [sql_simp, Resolved.comparisonOperands, comparisonAffinity, Value.isNull, Comparison.holds]
    intro named
    rw [named]
  · simp

/-- The guide's "the table has a column `status`", over every database that has a table `invoices`. -/
theorem invoices_has_a_status_column (db : Database) (position : Nat) (table : CatalogTable)
    (found : db.raw.catalog.findTable (name! "invoices") = some (position, table))
    (notFunction : db.raw.catalog.findTable (name! "pragma_table_info") = none) :
    Holds (sql r"SELECT 1 FROM pragma_table_info('invoices') WHERE name = 'status'") db ↔
      ∃ column ∈ table.columns, column.generated.isNone = true ∧ column.name.bytes = bytes! "status" :=
  table_has_a_stored_column_named db (bytes! "invoices") (bytes! "status") position table rfl found notFunction

/-- The table lookup ignores ASCII case: with `'INVOICES'` the same table is read. -/
theorem upper_case_table_name_reads_the_same_table (db : Database) (position : Nat) (table : CatalogTable)
    (found : db.raw.catalog.findTable (name! "invoices") = some (position, table))
    (notFunction : db.raw.catalog.findTable (name! "pragma_table_info") = none) :
    Holds (sql r"SELECT 1 FROM pragma_table_info('INVOICES') WHERE name = 'status'") db ↔
      ∃ column ∈ table.columns, column.generated.isNone = true ∧ column.name.bytes = bytes! "status" :=
  table_has_a_stored_column_named db (bytes! "INVOICES") (bytes! "status") position table rfl
    ((Catalog.findTable_sameName _ _ _ (by decide)).trans found) notFunction

/-- The test `name = 'c'` is a comparison of bytes: with `'Status'` the column `status` does not match. -/
theorem the_name_test_is_case_sensitive (db : Database) (position : Nat) (table : CatalogTable)
    (found : db.raw.catalog.findTable (name! "invoices") = some (position, table))
    (notFunction : db.raw.catalog.findTable (name! "pragma_table_info") = none) :
    Holds (sql r"SELECT 1 FROM pragma_table_info('invoices') WHERE name = 'Status'") db ↔
      ∃ column ∈ table.columns, column.generated.isNone = true ∧ column.name.bytes = bytes! "Status" :=
  table_has_a_stored_column_named db (bytes! "invoices") (bytes! "Status") position table rfl found notFunction

-- The instances on `shop`, whose table `invoices` has the columns `id`, `customer`, `amount` and `status`.

/-- On `shop`, the table `invoices` has a stored column `status`. -/
theorem shop_has_a_status_column :
    Holds (sql r"SELECT 1 FROM pragma_table_info('invoices') WHERE name = 'status'") shop :=
  (invoices_has_a_status_column shop invoices.1 invoices.2 (by decide +kernel) (by decide +kernel)).2 (by decide +kernel)

/-- On `shop`, the table name `'INVOICES'` reads the table `invoices`, which has a stored column `status`. -/
theorem shop_has_a_status_column_under_upper_case_table_name :
    Holds (sql r"SELECT 1 FROM pragma_table_info('INVOICES') WHERE name = 'status'") shop :=
  (upper_case_table_name_reads_the_same_table shop invoices.1 invoices.2 (by decide +kernel) (by decide +kernel)).2
    (by decide +kernel)

/-- On `shop`, no stored column of `invoices` is named `Status` with a capital: the name test is case-sensitive. -/
theorem shop_has_no_column_named_with_a_capital :
    ¬ Holds (sql r"SELECT 1 FROM pragma_table_info('invoices') WHERE name = 'Status'") shop :=
  fun holds => by
    have := (the_name_test_is_case_sensitive shop invoices.1 invoices.2 (by decide +kernel) (by decide +kernel)).1 holds
    revert this
    decide +kernel

set_option doc.verso true

/-- Over every database with an invoices table and no table that shadows the pragma function, the status-name query
is empty exactly when its name comparison is false on every pragma row, and it never fails. Proof sketch: resolve the
name cell once, then apply {name}`Empty.iff_selectOne_tableInfo` and {name}`Fails.not_selectOne_tableInfo`. -/
theorem status_column_empty_and_safe (db : Database) (position : Nat) (table : CatalogTable)
    (found : db.raw.catalog.findTable (name! "invoices") = some (position, table))
    (notFunction : db.raw.catalog.findTable (name! "pragma_table_info") = none) :
    (Empty (sql r"SELECT 1 FROM pragma_table_info('invoices') WHERE name = 'status'") db ↔
      ∀ row ∈ table.infoRows.map (· ++ [Value.text (bytes! "invoices"), Value.null]),
        Resolved.truthy ((Resolved.Expr.compare .eq (comparisonAffinity (some .blob) none) (.column 1)
          (.literal (.text (bytes! "status"))) .binary).eval (Resolved.EvalContext.bound []) row) = false) ∧
    ¬ Fails (sql r"SELECT 1 FROM pragma_table_info('invoices') WHERE name = 'status'") db := by
  have info := Catalog.tableInfoRows_of_findTable _ _ _ _ found
  have resolves : FilterResolves runContext.profile.dqsDml
      (tableInfoScope ⟨name! "pragma_table_info", none, some [.string (bytes! "invoices")]⟩ (bytes! "invoices") table.infoRows) []
      (some (.compare .eq (.identifier (name! "name") .none) (.string (bytes! "status"))))
      (some (.compare .eq (comparisonAffinity (some .blob) none) (.column 1) (.literal (.text (bytes! "status"))))) :=
    FilterResolves.of_term (result := (.compare .eq (comparisonAffinity (some .blob) none) (.column 1)
      (.literal (.text (bytes! "status"))) .binary, none)) (by simp [namesAlias]) (by simp [sql_simp])
  constructor
  · simpa using Empty.iff_selectOne_tableInfo (head := rfl) rfl
      (by simp [Identifier.isKeyword, equalsKeyword]; decide +kernel) notFunction info resolves (by simp [sql_simp])
  · exact Fails.not_selectOne_tableInfo (head := rfl) rfl
      (by simp [Identifier.isKeyword, equalsKeyword]; decide +kernel) notFunction info resolves (by simp [sql_simp])

/-- An existing table whose schema has no status column. The pragma query succeeds with no matching row. -/
def noStatus : Database := db! r"CREATE TABLE invoices (id INTEGER PRIMARY KEY);"

/-- The schema without a status column, for the positive Empty observation. -/
def noStatusTable : CatalogTable := (noStatus.raw.catalog.findTable (name! "invoices")).get (by decide +kernel) |>.2

example : Empty (sql r"SELECT 1 FROM pragma_table_info('invoices') WHERE name = 'status'") noStatus :=
  (status_column_empty_and_safe noStatus 0 noStatusTable (by decide +kernel) (by decide +kernel)).1.2 (by decide +kernel)
example : ¬ Empty (sql r"SELECT 1 FROM pragma_table_info('invoices') WHERE name = 'status'") shop := by
  rw [(status_column_empty_and_safe shop invoices.1 invoices.2 (by decide +kernel) (by decide +kernel)).1]
  decide +kernel
example : ¬ Fails (sql r"SELECT 1 FROM pragma_table_info('invoices') WHERE name = 'status'") noStatus :=
  (status_column_empty_and_safe noStatus 0 noStatusTable (by decide +kernel) (by decide +kernel)).2
example : ¬ Fails (sql r"SELECT 1 FROM pragma_table_info('invoices') WHERE name = 'status'") shop :=
  (status_column_empty_and_safe shop invoices.1 invoices.2 (by decide +kernel) (by decide +kernel)).2
