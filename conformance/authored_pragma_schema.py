"""The authored cases of `PRAGMA table_info`, `PRAGMA foreign_key_list`, their table-valued forms
and `PRAGMA recursive_triggers` (ADR 0019, slice 2; plans/20261023-pragmas.task.md, outcomes 6
to 9).

The cases of `table_info` and `foreign_key_list` cover each column and key form: declared types
as written, defaults, NOT NULL, the key columns of a `WITHOUT ROWID` table, generated columns,
composite keys and the actions. The table-valued forms run with `ORDER BY`, `WHERE` and a join.
The case of `recursive_triggers` runs under the profile with the setting on. Native SQLite is
the only source of outcomes.
"""

from conformance.authored_pragmas import PragmaCase
from conformance.pragma_requirements import CID_RANK, FK_LIST, RECURSIVE, REPLACE_TRIGGERS, TABLE_INFO

COLUMNS = ("CREATE TABLE t(a INTEGER PRIMARY KEY, b VARCHAR ( 10 ) NOT NULL DEFAULT 'x', g AS (a + 1), "
           "c int DEFAULT 3, \"d\" \"x\"\"y\" DEFAULT NULL, e, f TEXT DEFAULT -5 COLLATE NOCASE, "
           "h AS (b || 'h') STORED, i blob DEFAULT x'00'); "
           "CREATE TABLE w(k, v TEXT, n, PRIMARY KEY (v, k)) WITHOUT ROWID;")
"""A rowid table with each declared type form, each literal default form and generated columns between
the other columns, and a `WITHOUT ROWID` table with a composite primary key."""

KEYS = ("CREATE TABLE p(id INTEGER PRIMARY KEY, k1, k2, UNIQUE (k1, k2)); "
        "CREATE TABLE c(a, x REFERENCES p, y REFERENCES p(id) ON DELETE CASCADE ON UPDATE SET NULL, b, "
        "FOREIGN KEY (a, b) REFERENCES p(k1, k2) ON DELETE RESTRICT ON UPDATE NO ACTION, "
        "FOREIGN KEY (b) REFERENCES missing ON DELETE SET DEFAULT);")
"""A child with column keys with and without a column list and actions, and table keys with
two columns and to a missing parent."""


def schema_definitions() -> list[PragmaCase]:
    """The cases of `table_info`, `foreign_key_list`, their table-valued forms and
    `recursive_triggers`."""
    case = PragmaCase
    return [
        case("table-info-columns", COLUMNS,
             "PRAGMA table_info(t); PRAGMA table_info = 'w'; PRAGMA TABLE_INFO(\"t\"); PRAGMA table_info(nosuch);",
             (TABLE_INFO, CID_RANK), ("table-info", "generated", "without-rowid", "missing-table")),
        case("foreign-key-list-keys", KEYS,
             "PRAGMA foreign_key_list(c); PRAGMA foreign_key_list = 'p'; PRAGMA foreign_key_list(nosuch);",
             (FK_LIST,), ("foreign-key-list", "composite", "actions")),
        case("table-info-function", COLUMNS,
             "SELECT name, type, cid FROM pragma_table_info('t') ORDER BY name DESC; "
             "SELECT * FROM pragma_table_info('w') WHERE pk > 0 ORDER BY pk; "
             "SELECT count(*), max(cid) FROM pragma_table_info('t') WHERE dflt_value IS NOT NULL; "
             "SELECT name FROM pragma_table_info('t') WHERE dflt_value = 3; "
             "SELECT name FROM pragma_table_info('nosuch');",
             (TABLE_INFO, CID_RANK), ("table-info", "table-valued", "order-by", "where")),
        case("foreign-key-list-function", KEYS + "CREATE TABLE names(n TEXT); INSERT INTO names VALUES('a'), ('y');",
             "SELECT id, seq, \"from\", \"to\", on_delete FROM pragma_foreign_key_list('c') ORDER BY id DESC, seq; "
             "SELECT f.id AS fid, f.seq AS fseq, f.\"table\", i.name, i.pk FROM pragma_foreign_key_list('c') AS f "
             "JOIN pragma_table_info('c') AS i ON i.name = f.\"from\" ORDER BY fid, fseq; "
             "SELECT n, f.id AS fid FROM names LEFT JOIN pragma_foreign_key_list('c') AS f ON f.\"from\" = n "
             "ORDER BY n, fid;",
             (FK_LIST,), ("foreign-key-list", "table-valued", "join")),
        case("recursive-triggers-on",
             "CREATE TABLE t(id INTEGER PRIMARY KEY, v); CREATE TABLE u(k UNIQUE, v); CREATE TABLE log(m); "
             "CREATE TRIGGER s AFTER INSERT ON t WHEN new.v < 5 BEGIN INSERT INTO t VALUES(NULL, new.v + 1); END; "
             "CREATE TRIGGER d BEFORE DELETE ON u BEGIN INSERT INTO log VALUES('d' || old.v); END;",
             "PRAGMA recursive_triggers; INSERT INTO t VALUES(NULL, 1); SELECT * FROM t ORDER BY id; "
             "INSERT INTO u VALUES(1, 'a'), (2, 'b'); INSERT OR REPLACE INTO u VALUES(1, 'c'); "
             "REPLACE INTO u VALUES(2, 'e'); SELECT * FROM u ORDER BY k; SELECT * FROM log ORDER BY m;",
             (RECURSIVE, REPLACE_TRIGGERS), ("recursive-triggers", "trigger", "replace"), recursive=True),
    ]
