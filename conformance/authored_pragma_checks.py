"""The authored cases of the check pragmas and of `PRAGMA foreign_key_check` (ADR 0019, slice 2;
plans/20261023-pragmas.task.md, outcomes 1 to 5).

No modeled statement reaches a database whose constraints fail, so the cases of
`integrity_check` and `quick_check` show the row `ok` after writes of each constraint kind,
with a limit and with a table name. The cases of `foreign_key_check` run with foreign keys off,
so that the writes keep child rows without a parent. Each such case has one failing table: with
two or more, the model does not describe the order of the rows. Native SQLite is the only
source of outcomes.
"""

from conformance.authored_pragmas import PragmaCase
from conformance.pragma_requirements import (
    CHECK_OK, CHECK_LIMIT, CHECK_LOOKS_FOR, QUICK_CHECK, FK_CHECK, FK_CHECK_FORMS, FK_CHECK_ID)

CONSTRAINTS = ("CREATE TABLE t(a INTEGER PRIMARY KEY, b TEXT NOT NULL, c CHECK (c > 0), d UNIQUE); "
               "CREATE INDEX tb ON t(b); CREATE UNIQUE INDEX tc ON t(c, d); "
               "CREATE TABLE s(x INTEGER NOT NULL, y TEXT, z REAL) STRICT; "
               "CREATE TABLE w(k TEXT, v, PRIMARY KEY (k), UNIQUE (v)) WITHOUT ROWID; "
               "CREATE UNIQUE INDEX wn ON w(v COLLATE NOCASE) WHERE v > 'a';")
"""Tables with NOT NULL, CHECK, UNIQUE, a unique index with a condition, STRICT and WITHOUT
ROWID, and their indexes."""

WRITES = ("INSERT INTO t VALUES(1, 'x', 1, 'a'), (2, 'y', 2, NULL), (NULL, 'z', 3, NULL); "
          "INSERT INTO s VALUES(1, 'one', 2), (2, NULL, 2.5); INSERT INTO w VALUES('k1', 'A'), ('k2', 'b'), ('k3', NULL); "
          "UPDATE t SET b = b || 'u' WHERE a > 1; DELETE FROM w WHERE k = 'k2'; INSERT OR REPLACE INTO t VALUES(1, 'r', 5, 'a'); ")
"""Writes of rows to each table of {CONSTRAINTS}, also an UPDATE, a DELETE and a REPLACE."""

PARENTS = ("CREATE TABLE p(id INTEGER PRIMARY KEY, v); CREATE TABLE q(k PRIMARY KEY, v); "
           "CREATE TABLE r(n TEXT COLLATE NOCASE UNIQUE); "
           "INSERT INTO p VALUES(1, 'a'), (2, 'b'); INSERT INTO q VALUES('1', 'a'), (2, 'b'); "
           "INSERT INTO r VALUES('Ab'), ('cd');")
"""Parents with a rowid key, a primary key that is no rowid, and a UNIQUE key with NOCASE."""


def check_definitions() -> list[PragmaCase]:
    """The cases of `integrity_check`, `quick_check` and `foreign_key_check`."""
    case = PragmaCase
    return [
        case("check-ok-after-writes", CONSTRAINTS,
             WRITES + "PRAGMA integrity_check; PRAGMA quick_check; PRAGMA Integrity_Check;",
             (CHECK_OK, CHECK_LOOKS_FOR, QUICK_CHECK), ("integrity-check", "quick-check", "writes")),
        case("check-ok-limit-table", CONSTRAINTS,
             WRITES + "PRAGMA integrity_check(1); PRAGMA quick_check = 5; PRAGMA integrity_check(-2); "
             "PRAGMA integrity_check(t); PRAGMA quick_check(w); PRAGMA integrity_check = 's'; PRAGMA quick_check('5');",
             (CHECK_OK, CHECK_LIMIT, QUICK_CHECK), ("integrity-check", "quick-check", "limit", "table-name")),
        case("check-missing-table", CONSTRAINTS, "PRAGMA quick_check(t); PRAGMA integrity_check(nosuch);",
             (CHECK_OK,), ("integrity-check", "missing-table")),
        case("foreign-key-check-rowid", PARENTS + "CREATE TABLE c(x REFERENCES p, w);",
             "INSERT INTO c VALUES(1, 'ok'), (3, 'fails'), (NULL, 'null'), ('1.0', 'text'), (' 1', 'space'), (1.5, 'real'); "
             "PRAGMA foreign_key_check; PRAGMA foreign_key_check(c); PRAGMA foreign_key_check(p); "
             "DELETE FROM p WHERE id = 1; PRAGMA foreign_key_check = c;",
             (FK_CHECK, FK_CHECK_FORMS), ("foreign-key-check", "rowid-parent", "keys-off")),
        case("foreign-key-check-primary-key", PARENTS + "CREATE TABLE c(x REFERENCES q, y REFERENCES q(k));",
             "INSERT INTO c VALUES('1', 1), (2, '2'), (1.0, 3), (X'01', NULL); "
             "PRAGMA foreign_key_check; PRAGMA foreign_key_check(c);",
             (FK_CHECK, FK_CHECK_ID), ("foreign-key-check", "primary-key-parent", "fkid")),
        case("foreign-key-check-collation", PARENTS + "CREATE TABLE c(x TEXT REFERENCES r(n));",
             "INSERT INTO c VALUES('ab'), ('CD'), ('ef'), (NULL); UPDATE r SET n = 'zz' WHERE n = 'cd'; "
             "PRAGMA foreign_key_check; PRAGMA foreign_key_check('c');",
             (FK_CHECK,), ("foreign-key-check", "unique-parent", "collation")),
        case("foreign-key-check-missing-parent", PARENTS + "CREATE TABLE c(x REFERENCES missing(id), y REFERENCES p);",
             "INSERT INTO c VALUES(1, 1), (NULL, 2), (2, 5); PRAGMA foreign_key_check; PRAGMA foreign_key_check(c);",
             (FK_CHECK, FK_CHECK_ID), ("foreign-key-check", "missing-parent")),
        case("foreign-key-check-without-rowid",
             PARENTS + "CREATE TABLE c(k PRIMARY KEY, x REFERENCES p, FOREIGN KEY (k) REFERENCES q) WITHOUT ROWID;",
             "INSERT INTO c VALUES('1', 1), ('2', 7), (9, 2), (8, NULL); PRAGMA foreign_key_check; "
             "PRAGMA foreign_key_check(c);",
             (FK_CHECK, FK_CHECK_ID), ("foreign-key-check", "without-rowid")),
        case("foreign-key-check-one-table",
             PARENTS + "CREATE TABLE c(x REFERENCES p); CREATE TABLE d(y REFERENCES q); "
             "INSERT INTO d VALUES('1'), (2);",
             "INSERT INTO c VALUES(1), (4); PRAGMA foreign_key_check; PRAGMA foreign_key_check(c); "
             "PRAGMA foreign_key_check(d);",
             (FK_CHECK, FK_CHECK_FORMS), ("foreign-key-check", "table-name")),
        case("foreign-key-check-mismatch",
             "CREATE TABLE p(a, b UNIQUE); CREATE TABLE c(x REFERENCES p(a)); CREATE TABLE d(y REFERENCES p(b));",
             "INSERT INTO c VALUES(1); PRAGMA foreign_key_check(d); PRAGMA foreign_key_check(c);",
             (FK_CHECK,), ("foreign-key-check", "mismatch")),
        case("foreign-key-check-mismatch-all",
             "CREATE TABLE p(a, b UNIQUE); CREATE TABLE c(x REFERENCES p(a)); CREATE TABLE d(y REFERENCES p(b));",
             "INSERT INTO d VALUES(5); PRAGMA foreign_key_check;",
             (FK_CHECK,), ("foreign-key-check", "mismatch")),
        case("foreign-key-check-missing-table", PARENTS, "PRAGMA foreign_key_check(p); PRAGMA foreign_key_check(nosuch);",
             (FK_CHECK_FORMS,), ("foreign-key-check", "missing-table")),
    ]
