"""Authored cases of what each statement does to the connection counters (ADR 0024, D1 and D2).

The cases read `changes()`, `total_changes()` and `last_insert_rowid()` after the statements that
the ADR's table of facts names, when they succeed: the start of a connection, the writes of the
setup, INSERT with IGNORE and REPLACE, UPDATE, DELETE, upserts, a `WITHOUT ROWID` table, the
statements that leave the counters, the writes with trigger programs and with foreign-key actions,
and `DROP TABLE`. The cases use `conformance.authored_queries.QueryCase`.
"""

from conformance.authored_queries import QueryCase
from conformance.counter_sql import LOGGED, PARENT, PLAIN, READ, REFERENCED, ROWS


def definitions() -> list[QueryCase]:
    """The cases of the writes that succeed."""
    case = QueryCase
    return [
        case("new-connection", ROWS, READ + " INSERT INTO t VALUES (5, 'x');" + READ,
             ("R-38914-26427", "R-14350-55458"), ("counters", "start")),
        case("setup-leaves-counters", ROWS + " UPDATE t SET b = 'z' WHERE a = 1;",
             READ + " DELETE FROM t WHERE a = 3;" + READ, ("R-38914-26427", "R-58361-29089"), ("counters", "start")),
        case("insert-sets-counters", ROWS, "INSERT INTO t VALUES (10, 'x'), (11, 'y'), (12, 'z');" + READ +
             " INSERT INTO t(b) VALUES ('w');" + READ,
             ("R-58361-29089", "R-14875-52970", "R-36596-35603"), ("counters", "insert")),
        case("insert-or-ignore-skips", ROWS, "INSERT OR IGNORE INTO t VALUES (1, 'z'), (9, 'a');" + READ +
             " INSERT OR IGNORE INTO t VALUES (8, 'h'), (3, 'c');" + READ,
             ("R-09702-18252", "R-58361-29089"), ("counters", "insert", "ignore")),
        case("insert-or-replace", ROWS, "INSERT OR REPLACE INTO t VALUES (2, 'c');" + READ,
             ("R-36043-10590", "R-48887-45097"), ("counters", "insert", "replace")),
        case("insert-or-replace-with-foreign-keys", ROWS + " CREATE TABLE q(x REFERENCES t(a)); INSERT INTO q VALUES (1);",
             "INSERT OR REPLACE INTO t VALUES (7, 'c');" + READ,
             ("R-36043-10590", "R-48887-45097"), ("counters", "insert", "replace", "foreign-key")),
        case("update-counts", PLAIN, "UPDATE t SET b = b;" + READ + " UPDATE t SET b = 'q' WHERE a > 100;" + READ +
             " UPDATE t SET b = b || 'x' WHERE a = 2;" + READ, ("R-58361-29089",), ("counters", "update")),
        case("delete-counts", ROWS, "DELETE FROM t WHERE a = 2;" + READ + " DELETE FROM t;" + READ +
             " DELETE FROM t;" + READ, ("R-58361-29089",), ("counters", "delete")),
        case("upsert-counts", ROWS, "INSERT INTO t VALUES (1, 'z') ON CONFLICT(a) DO UPDATE SET b = 'u';" + READ +
             " INSERT INTO t VALUES (2, 'z') ON CONFLICT DO NOTHING;" + READ +
             " INSERT INTO t VALUES (7, 'y'), (3, 'c') ON CONFLICT(a) DO UPDATE SET b = excluded.b || '!';" + READ,
             ("R-58361-29089", "R-36596-35603"), ("counters", "upsert")),
        case("without-rowid-leaves-last-rowid", ROWS + " CREATE TABLE w(k INTEGER PRIMARY KEY, v) WITHOUT ROWID;",
             "INSERT INTO w VALUES (50, 1), (51, 2);" + READ + " INSERT INTO t VALUES (60, 'n');" + READ +
             " INSERT INTO w VALUES (70, 3);" + READ, ("R-47220-63683", "R-40676-08516"), ("counters", "without-rowid")),
        case("statements-that-leave-the-counters", ROWS + " INSERT INTO t VALUES (20, 'k');",
             READ + " SELECT a FROM t; CREATE TABLE u(x); CREATE INDEX i ON t(b); ALTER TABLE u ADD COLUMN y; "
             "DROP INDEX i; BEGIN; COMMIT; PRAGMA table_info(t); DROP TABLE u;" + READ,
             ("R-61766-15253",), ("counters", "other-statements")),
        case("rollback-keeps-the-counters", ROWS, "BEGIN; INSERT INTO t VALUES (20, 'n'), (21, 'o'); ROLLBACK;" + READ,
             ("R-15264-45364",), ("counters", "rollback")),
        case("trigger-programs-count", LOGGED, "INSERT INTO t VALUES (1, 'a'), (2, 'b');" + READ +
             " UPDATE t SET b = b || '!';" + READ + " DELETE FROM t WHERE a = 1;" + READ,
             ("R-58361-29089", "R-23547-15805", "R-32918-61474"), ("counters", "trigger")),
        case("foreign-key-actions-count", PARENT, "DELETE FROM p WHERE id = 1;" + READ +
             " UPDATE p SET id = 20 WHERE id = 2;" + READ + " DELETE FROM p WHERE k = 'c';" + READ,
             ("R-36043-10590", "R-23547-15805"), ("counters", "foreign-key", "action")),
        case("drop-table-with-foreign-key-actions", REFERENCED, "DROP TABLE p;" + READ + " SELECT x FROM c;",
             ("R-36043-10590", "R-23547-15805"), ("counters", "foreign-key", "drop-table")),
        case("drop-table-fails-after-actions", REFERENCED + " CREATE TABLE d(y REFERENCES p); INSERT INTO d VALUES (2);",
             "DROP TABLE p;" + READ, ("R-23547-15805",), ("counters", "foreign-key", "drop-table", "constraint-failure")),
        case("drop-table-without-references", ROWS, "DROP TABLE t;" + READ,
             ("R-61766-15253",), ("counters", "foreign-key", "drop-table")),
    ]
