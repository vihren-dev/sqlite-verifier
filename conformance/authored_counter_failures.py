"""Authored cases of the connection counters after a statement that fails (ADR 0024, D1 and D2).

A write that fails with ABORT or ROLLBACK leaves `changes()` 0. A write that fails with FAIL keeps
the count of the rows that it completed. Every failed write keeps the rows of its completed
trigger programs and foreign-key actions in `total_changes()`, and leaves `last_insert_rowid()`
at the rowid of the last row that the write inserted before the failure; the rollback does not
take these back. The cases cover each way a write fails, the algorithms FAIL and ROLLBACK, a failure
in a transaction, a statement that fails to prepare, and the foreign-key checks that fail at the
end of the statement or when an action runs. The cases use `conformance.authored_queries.QueryCase`.
"""

from conformance.authored_queries import QueryCase
from conformance.counter_sql import (BOUNDED, CHECKED, CHILD, EXITING, RAISING, READ, RESTRICTED, ROWS)

CASCADED = ("CREATE TABLE t(a INTEGER PRIMARY KEY); CREATE TABLE log(x); "
            "CREATE TRIGGER i AFTER INSERT ON t BEGIN INSERT INTO log VALUES (new.a), (new.a); END;")
"""A table whose AFTER INSERT trigger writes two rows into a log."""


def definitions() -> list[QueryCase]:
    """The cases of the writes that fail, and of the statements that stop before they run."""
    case = QueryCase
    return [
        case("failed-insert-keeps-the-rowid", ROWS, "INSERT INTO t VALUES (10, 'x'), (11, 'y');" + READ +
             " INSERT INTO t(b) VALUES ('new'), ('a');" + READ + " INSERT INTO t VALUES (1, 'zz');" + READ,
             ("R-29588-44058", "R-09702-18252"), ("counters", "failure", "abort")),
        case("failed-insert-at-each-constraint", CHECKED,
             "INSERT INTO n VALUES (10, 'x', 1); INSERT INTO n VALUES (20, 'x', 1), (21, NULL, 1);" + READ +
             " INSERT INTO n VALUES (30, 'x', 1), (31, 'x', 1), (32, 'x', -1);" + READ +
             " INSERT INTO n VALUES (40, 'x', 1), ('abc', 'x', 1);" + READ + " INSERT INTO n VALUES (50, NULL, 1);" + READ,
             ("R-29588-44058",), ("counters", "failure", "not-null", "check", "datatype-mismatch")),
        case("insert-or-fail-keeps-the-rows", ROWS, "INSERT OR FAIL INTO t VALUES (10, 'x'), (11, 'a'), (12, 'z');" + READ,
             ("R-09702-18252", "R-58361-29089"), ("counters", "failure", "fail")),
        case("failed-update-keeps-total-changes", BOUNDED, "UPDATE k SET v = v * 4;" + READ +
             " UPDATE k SET v = v + 1 WHERE a < 3;" + READ + " DELETE FROM k WHERE a = 1;" + READ,
             ("R-58361-29089", "R-38914-26427"), ("counters", "failure", "update")),
        case("failed-write-after-trigger-rows", RAISING, "INSERT INTO t VALUES (1), (2);" + READ +
             " INSERT INTO t VALUES (3), (-1), (4);" + READ,
             ("R-23547-15805",), ("counters", "failure", "trigger", "raise")),
        case("raise-in-after-and-before-triggers", EXITING,
             "INSERT INTO t VALUES (20, 1), (21, -1), (22, 1);" + READ + " INSERT INTO t VALUES (40, 1), (41, -9);" + READ,
             ("R-29588-44058", "R-46934-63022"), ("counters", "failure", "trigger", "raise")),
        case("failed-write-in-a-transaction", ROWS, "BEGIN; INSERT INTO t VALUES (10, 'x'); "
             "INSERT INTO t VALUES (11, 'y'), (12, 'a');" + READ + " ROLLBACK;" + READ,
             ("R-15264-45364", "R-29588-44058"), ("counters", "failure", "transaction", "rollback")),
        case("or-rollback-failure", ROWS, "INSERT INTO t VALUES (10, 'x'); BEGIN; INSERT INTO t VALUES (11, 'y'); "
             "INSERT OR ROLLBACK INTO t VALUES (12, 'q'), (13, 'a');" + READ,
             ("R-15264-45364",), ("counters", "failure", "rollback")),
        case("prepare-errors-keep-the-counters", ROWS + " INSERT INTO t VALUES (9, 'i');",
             "INSERT INTO missing VALUES (1); SELECT nope FROM t;" + READ,
             ("R-61766-15253",), ("counters", "failure", "prepare-error")),
        case("or-fail-with-trigger-rows", CASCADED, "INSERT OR FAIL INTO t VALUES (5), (5);" + READ +
             " INSERT INTO t VALUES (6), (6);" + READ,
             ("R-23547-15805", "R-09702-18252"), ("counters", "failure", "fail", "trigger")),
        case("missing-parent-at-the-end-of-the-statement", CHILD,
             "INSERT INTO ch VALUES (30, 1), (31, 2), (32, 1);" + READ + " INSERT INTO ch VALUES (40, 2);" + READ +
             " INSERT INTO ch VALUES (50, 1);" + READ,
             ("R-29588-44058",), ("counters", "failure", "foreign-key")),
        case("restrict-action-fails-during-replace", RESTRICTED, "INSERT OR REPLACE INTO p VALUES (7, 7), (8, 1);" + READ +
             " INSERT OR REPLACE INTO p VALUES (1, 2);" + READ,
             ("R-29588-44058", "R-48887-45097"), ("counters", "failure", "foreign-key", "replace")),
    ]
