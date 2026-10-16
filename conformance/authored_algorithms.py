"""Authored coverage cases of conflict algorithms (ADR 0012, amendment 4, slice 5d).

The cases follow the "Tests" list of the slice 5d task: each algorithm of `INSERT OR`
and `REPLACE INTO` on a key failure and on a NOT NULL failure; FAIL with earlier rows and
with `RETURNING`; REPLACE of two conflicting rows, of a rowid alias and of a NULL in a
NOT NULL column; ROLLBACK inside and outside a transaction; a rowid alias mismatch under
FAIL and IGNORE; and an UPSERT with an `OR` clause. Native SQLite is the only source of
outcomes. The cases use `conformance.authored_queries.QueryCase` and its recorder.
"""

from conformance.authored_queries import QueryCase, records as query_records
from conformance.case_format import Json

TABLES = ("CREATE TABLE t(k INTEGER UNIQUE, u INTEGER UNIQUE, v TEXT NOT NULL); "
          "CREATE TABLE i(id INTEGER PRIMARY KEY, v); "
          "INSERT INTO t VALUES(1, 1, 'a'), (2, 2, 'b'); INSERT INTO i VALUES(1, 'a');")
"""A table with two keys and a NOT NULL column, and a table with a rowid alias."""

CONSTRAINTS = ("CREATE TABLE ci(k INTEGER UNIQUE ON CONFLICT IGNORE, v); "
               "CREATE TABLE cr(k INTEGER PRIMARY KEY ON CONFLICT REPLACE, v); "
               "CREATE TABLE cn(k UNIQUE, v NOT NULL ON CONFLICT IGNORE); "
               "CREATE TABLE cf(k INTEGER, v, UNIQUE(k) ON CONFLICT FAIL); "
               "CREATE TABLE cm(k INTEGER UNIQUE ON CONFLICT REPLACE, u INTEGER UNIQUE, v); "
               "CREATE TABLE cu(k UNIQUE ON CONFLICT REPLACE, v, UNIQUE(k)); "
               "INSERT INTO ci VALUES(1, 'a'); INSERT INTO cr VALUES(1, 'a'); INSERT INTO cn VALUES(1, 'a'); "
               "INSERT INTO cf VALUES(1, 'a'); INSERT INTO cm VALUES(1, 1, 'a'), (2, 2, 'b'); "
               "INSERT INTO cu VALUES(1, 'a');")
"""Tables whose constraints have ON CONFLICT algorithms: a column and a table constraint,
a rowid alias, NOT NULL, a REPLACE key beside an ABORT key, and two constraints of one
index, whose explicit algorithm applies."""

FAIL = "R-31882-08811"
"""SQLite: the FAIL algorithm does not back out the prior changes of the failing statement."""
ROLLBACK = "R-31881-13880"
"""SQLite: the ROLLBACK algorithm aborts the statement and rolls back the transaction."""
ROLLBACK_IDLE = "R-42089-41020"
"""SQLite: without an active transaction, the ROLLBACK algorithm works as ABORT."""
IGNORE = "R-50299-05307"
"""SQLite: the IGNORE algorithm skips the one row that has the constraint violation."""
REPLACE = "R-54702-17780"
"""SQLite: on a UNIQUE or PRIMARY KEY violation, REPLACE deletes the rows that cause it."""
REPLACE_NULL = "R-12527-00403"
"""SQLite: REPLACE of a NULL in a NOT NULL column uses the default, or ABORT without one."""
REPLACE_COUNT = "R-37019-57602"
"""SQLite: the rows that REPLACE deletes do not increment the change counter."""
CONSTRAINT = "R-34093-09213"
"""SQLite: PRIMARY KEY, UNIQUE and NOT NULL constraints may have another default algorithm."""
REPLACE_INTO = "R-00267-47727"
"""SQLite: INSERT can be replaced by REPLACE or INSERT OR action to name another algorithm."""
OVERRIDE = "R-33948-22286"
"""SQLite: the algorithm of the OR clause overrides the algorithm of a constraint."""


def definitions() -> list[QueryCase]:
    """The coverage cases of conflict algorithms."""
    case = QueryCase
    conflict = "VALUES(3, 3, 'c'), (1, 9, 'x'), (4, 4, 'd')"
    return [
        case("or-abort", TABLES, f"INSERT OR ABORT INTO t {conflict};", (OVERRIDE,), ("algorithm", "abort")),
        case("or-fail", TABLES, f"INSERT OR FAIL INTO t {conflict};", (FAIL,), ("algorithm", "fail")),
        case("or-fail-returning", TABLES, f"INSERT OR FAIL INTO t {conflict} RETURNING k;", (FAIL,),
             ("algorithm", "fail", "returning")),
        case("or-fail-not-null", TABLES, "INSERT OR FAIL INTO t VALUES(3, 3, 'c'), (5, 5, NULL);", (FAIL,),
             ("algorithm", "fail", "not-null")),
        case("or-fail-mismatch", TABLES, "INSERT OR FAIL INTO i VALUES(5, 'a'), ('x', 'b');", (FAIL,),
             ("algorithm", "fail", "mismatch")),
        case("or-fail-transaction", TABLES, f"BEGIN; INSERT OR FAIL INTO t {conflict};", (FAIL,),
             ("algorithm", "fail", "transaction")),
        case("or-ignore", TABLES, f"INSERT OR IGNORE INTO t {conflict} RETURNING *;", (IGNORE,),
             ("algorithm", "ignore")),
        case("or-ignore-not-null", TABLES, "INSERT OR IGNORE INTO t VALUES(5, 5, NULL), (6, 6, 'f') RETURNING *;",
             (IGNORE,), ("algorithm", "ignore", "not-null")),
        case("or-ignore-mismatch", TABLES, "INSERT OR IGNORE INTO i VALUES('x', 'b');", (IGNORE,),
             ("algorithm", "ignore", "mismatch")),
        case("or-replace-two-rows", TABLES, "INSERT OR REPLACE INTO t VALUES(1, 2, 'r') RETURNING *;",
             (REPLACE, REPLACE_COUNT), ("algorithm", "replace")),
        case("replace-into", TABLES, "REPLACE INTO t VALUES(2, 7, 's'), (8, 8, 'e') RETURNING *;",
             (REPLACE_INTO, REPLACE, REPLACE_COUNT), ("algorithm", "replace")),
        case("or-replace-alias", TABLES, "INSERT OR REPLACE INTO i VALUES(1, 'z') RETURNING *;", (REPLACE,),
             ("algorithm", "replace", "alias")),
        case("or-replace-null-alias", TABLES, "INSERT OR REPLACE INTO i VALUES(NULL, 'n') RETURNING *;", (REPLACE,),
             ("algorithm", "replace", "alias")),
        case("or-replace-not-null", TABLES, "INSERT OR REPLACE INTO t VALUES(7, 7, NULL);", (REPLACE_NULL,),
             ("algorithm", "replace", "not-null")),
        case("or-rollback-idle", TABLES, f"INSERT OR ROLLBACK INTO t {conflict};", (ROLLBACK_IDLE,),
             ("algorithm", "rollback")),
        case("or-rollback-transaction", TABLES,
             f"BEGIN; INSERT INTO t VALUES(9, 9, 'z'); INSERT OR ROLLBACK INTO t {conflict};", (ROLLBACK,),
             ("algorithm", "rollback", "transaction")),
        case("or-abort-transaction", TABLES,
             f"BEGIN; INSERT INTO t VALUES(9, 9, 'z'); INSERT OR ABORT INTO t {conflict};", (OVERRIDE,),
             ("algorithm", "abort", "transaction")),
        case("or-ignore-do-update-fails", TABLES,
             "INSERT OR IGNORE INTO t VALUES(1, 9, 'x') ON CONFLICT(k) DO UPDATE SET u = 2;", (IGNORE,),
             ("algorithm", "ignore", "upsert")),
        case("or-ignore-do-update", TABLES,
             "INSERT OR IGNORE INTO t VALUES(1, 9, 'x') ON CONFLICT(k) DO UPDATE SET v = 'w' RETURNING *;",
             (IGNORE,), ("algorithm", "ignore", "upsert")),
        case("or-replace-untargeted", TABLES,
             "INSERT OR REPLACE INTO t VALUES(9, 2, 'y') ON CONFLICT(k) DO NOTHING RETURNING *;",
             (REPLACE,), ("algorithm", "replace", "upsert")),
        case("constraint-ignore", CONSTRAINTS, "INSERT INTO ci VALUES(1, 'b'), (2, 'c') RETURNING *;",
             (CONSTRAINT, IGNORE), ("algorithm", "constraint", "ignore")),
        case("constraint-replace-alias", CONSTRAINTS, "INSERT INTO cr VALUES(1, 'b') RETURNING *;",
             (CONSTRAINT, REPLACE), ("algorithm", "constraint", "replace", "alias")),
        case("constraint-not-null-ignore", CONSTRAINTS, "INSERT INTO cn VALUES(2, NULL), (3, 'c') RETURNING *;",
             (CONSTRAINT, IGNORE), ("algorithm", "constraint", "not-null")),
        case("constraint-fail-table", CONSTRAINTS, "INSERT INTO cf VALUES(2, 'b'), (1, 'c');",
             (CONSTRAINT, FAIL), ("algorithm", "constraint", "fail")),
        case("constraint-or-overrides", CONSTRAINTS, "INSERT OR ABORT INTO ci VALUES(1, 'b');",
             (OVERRIDE,), ("algorithm", "constraint", "override")),
        case("constraint-replace-after-abort", CONSTRAINTS, "INSERT INTO cm VALUES(1, 2, 'x');",
             (CONSTRAINT, REPLACE), ("algorithm", "constraint", "order")),
        case("constraint-replace-other", CONSTRAINTS, "INSERT INTO cm VALUES(1, 9, 'y') RETURNING *;",
             (CONSTRAINT, REPLACE), ("algorithm", "constraint", "replace")),
        case("constraint-upsert-target-first", CONSTRAINTS,
             "INSERT INTO ci VALUES(1, 'b') ON CONFLICT(k) DO UPDATE SET v = 'u' RETURNING *;",
             (CONSTRAINT,), ("algorithm", "constraint", "upsert")),
        case("constraint-merged-index", CONSTRAINTS, "INSERT INTO cu VALUES(1, 'b') RETURNING *;",
             (CONSTRAINT, REPLACE), ("algorithm", "constraint", "merged")),
    ]


def records(cases: list[QueryCase] | None = None) -> list[dict[str, Json]]:
    """Record each case natively as a version 5 record with outputs, in the part `algorithms`."""
    return query_records(definitions() if cases is None else cases, part="algorithms")
