"""Neutral immediate-transaction groups retain native boundaries before model extension."""

from conformance.authored_cases import AuthoredCase


def definitions() -> list[AuthoredCase]:
    """Group schema, write and read SQL with explicit commit, rollback and failure boundaries."""
    setup = "CREATE TABLE ledger(id TEXT PRIMARY KEY,v INTEGER CHECK(v>0));" \
        "INSERT INTO ledger VALUES('seed',2);"
    return [
        AuthoredCase("immediate-schema-write-commit", setup,
            "BEGIN IMMEDIATE; ALTER TABLE ledger ADD note TEXT DEFAULT 'new';"
            "CREATE INDEX ledger_by_v ON ledger(v);"
            "INSERT INTO ledger(id,v) VALUES(?,?) RETURNING id,v,note;"
            "UPDATE ledger SET v=v+1 WHERE id=? RETURNING id,v;"
            "SELECT id,v,note FROM ledger ORDER BY id; COMMIT;"
            "SELECT id,v,note FROM ledger ORDER BY id;", (),
            ("transaction", "immediate", "commit", "add-column", "defaults", "indexes", "typed-parameters"),
            ((), (), (), ((3, b"kept"), (1, 7)), ((3, b"seed"),), (), (), ()), profile="immediate"),
        AuthoredCase("immediate-schema-write-rollback", setup,
            "BEGIN IMMEDIATE; CREATE TABLE transient(v INTEGER);"
            "INSERT INTO transient VALUES(?) RETURNING v;"
            "UPDATE ledger SET v=? WHERE id=? RETURNING id,v;"
            "SELECT id,v FROM ledger ORDER BY id; ROLLBACK;"
            "SELECT id,v FROM ledger ORDER BY id;", (),
            ("transaction", "immediate", "rollback", "create-table", "typed-parameters"),
            ((), (), ((1, 9),), ((1, 4), (3, b"seed")), (), (), ()), profile="immediate"),
        AuthoredCase("immediate-savepoint-rollback", setup,
            "BEGIN IMMEDIATE; INSERT INTO ledger VALUES(?,?) RETURNING id,v;"
            "SAVEPOINT inner; ALTER TABLE ledger ADD note TEXT DEFAULT 'temporary';"
            "INSERT INTO ledger(id,v) VALUES(?,?) RETURNING id,v;"
            "UPDATE ledger SET v=? WHERE id=?; SELECT id,v,note FROM ledger ORDER BY id;"
            "ROLLBACK TO inner; RELEASE inner; SELECT id,v FROM ledger ORDER BY id;"
            "COMMIT; SELECT id,v FROM ledger ORDER BY id;", (),
            ("transaction", "immediate", "savepoint", "rollback", "add-column", "typed-parameters"),
            ((), ((3, b"kept"), (1, 5)), (), (), ((3, b"discarded"), (1, 8)),
             ((1, 6), (3, b"seed")), (), (), (), (), (), ()), profile="immediate"),
        AuthoredCase("immediate-check-abort", setup,
            "BEGIN IMMEDIATE; INSERT INTO ledger VALUES(?,?) RETURNING id,v;"
            "SELECT id,v FROM ledger ORDER BY id;"
            "INSERT INTO ledger VALUES(?,?),(?,?) RETURNING id,v;"
            "COMMIT; SELECT id,v FROM ledger ORDER BY id;", (),
            ("transaction", "immediate", "check", "constraint-failure", "statement-rollback", "typed-parameters"),
            ((), ((3, b"kept"), (1, 5)), (),
             ((3, b"partial"), (1, 9), (3, b"bad"), (1, 0)), (), ()), profile="immediate"),
        AuthoredCase("immediate-deferred-commit-failure",
            "CREATE TABLE parent(id INTEGER PRIMARY KEY);"
            "CREATE TABLE child(id INTEGER PRIMARY KEY,pid REFERENCES parent(id) "
            "DEFERRABLE INITIALLY DEFERRED);",
            "BEGIN IMMEDIATE; INSERT INTO child VALUES(?,?) RETURNING id,pid;"
            "SELECT id,pid FROM child ORDER BY id; COMMIT;"
            "INSERT INTO parent VALUES(1); SELECT id,pid FROM child ORDER BY id;", (),
            ("transaction", "immediate", "foreign-key", "deferred-foreign-key", "constraint-failure", "typed-parameters"),
            ((), ((1, 10), (1, 1)), (), (), (), ()), profile="foreign-keys"),
    ]
