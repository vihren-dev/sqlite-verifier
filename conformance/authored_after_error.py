"""Authored cases of the statements after a failed statement (task "Evidence for the statements
after an error", outcome 8).

Each case has statements after a failed one that read or write what the failure left: prepare
errors in autocommit and inside a transaction, prepare errors that SQLite reports in the middle of
the text, a trigger body that names a dropped table, each conflict algorithm that fails inside a
transaction (the model does not describe `UPDATE` with the algorithm ROLLBACK, so no case has
one), errors in a trigger, transaction control, failures that change what later statements
see, a run error of a query, and an immediate foreign-key failure. The recorder runs on after an
error (`record_sql` with `run_on`), so each record has version 6. Native SQLite is the only source
of outcomes. The cases use `conformance.authored_queries.QueryCase`.
"""

from conformance import authored_foreign_keys, authored_resolution
from conformance.authored_queries import QueryCase
from conformance.case_format import Json
from conformance.native_record import record_sql

KEYS = "CREATE TABLE k(id INTEGER PRIMARY KEY, v TEXT UNIQUE); INSERT INTO k VALUES (1, 'a');"
"""A table with a UNIQUE column and one row, so that the value 'a' makes a conflict."""
ORDERED = " SELECT id, v FROM k ORDER BY id;"
"""The rows of `k` in key order."""
LOGGED = ("CREATE TABLE t(a INTEGER PRIMARY KEY); CREATE TABLE log(x UNIQUE); "
          "CREATE TRIGGER l AFTER INSERT ON t BEGIN INSERT INTO log VALUES (new.a); END;")
"""A table whose AFTER INSERT trigger writes each new key into a log with a UNIQUE column."""
BOTH = " SELECT a FROM t ORDER BY a; SELECT x FROM log ORDER BY x;"
"""The rows of `t` and of the log."""
FOREIGN_KEYS = frozenset({"immediate-foreign-key-in-transaction"})
"""The cases that run under the profile with foreign keys on."""


def raised(form: str) -> str:
    """`LOGGED` with a BEFORE INSERT trigger that raises with the form for a negative key."""
    return LOGGED + (f" CREATE TRIGGER g BEFORE INSERT ON t WHEN new.a < 0 BEGIN SELECT RAISE({form}, 'negative'); END;")


def definitions() -> list[QueryCase]:
    """The cases of the statements after a failed statement."""
    case = QueryCase
    return [
        case("prepare-errors-in-autocommit", KEYS,
             "INSERT INTO missing VALUES (1); SELECT nope FROM k; INSERT INTO k VALUES (2); "
             "INSERT INTO k VALUES (2, 'b');" + ORDERED,
             ("R-44050-47362",), ("prepare-error", "autocommit")),
        case("prepare-errors-in-transaction", KEYS,
             "BEGIN; INSERT INTO k VALUES (2, 'b'); INSERT INTO missing VALUES (1); SELECT nope FROM k; "
             "INSERT INTO k VALUES (3); INSERT INTO k VALUES (3, 'c'); COMMIT;" + ORDERED,
             ("R-44050-47362", "R-32090-20403"), ("prepare-error", "transaction")),
        case("prepare-errors-in-the-middle", KEYS,
             "CREATE TABLE u(a, a, b); CREATE TABLE k(z); "
             "CREATE TRIGGER r AFTER INSERT ON missing BEGIN INSERT INTO k VALUES (9, 'z'); END; "
             "CREATE TABLE u(c); INSERT INTO u VALUES (1); SELECT c FROM u;" + ORDERED,
             ("R-44050-47362",), ("prepare-error", "statement-boundary", "create-table")),
        case("trigger-body-names-a-dropped-table", LOGGED,
             "DROP TABLE log; INSERT INTO t VALUES (1); CREATE TABLE log(x UNIQUE); INSERT INTO t VALUES (2);" + BOTH,
             ("R-44050-47362",), ("prepare-error", "trigger", "drop-table")),
        case("abort-in-transaction", KEYS,
             "BEGIN; INSERT INTO k VALUES (2, 'b'); INSERT INTO k VALUES (3, 'c'), (4, 'a');" + ORDERED +
             " COMMIT;" + ORDERED,
             ("R-47224-48532",), ("constraint-failure", "abort", "transaction")),
        case("fail-in-transaction", KEYS,
             "BEGIN; INSERT OR FAIL INTO k VALUES (2, 'b'), (3, 'a'), (4, 'd');" + ORDERED + " COMMIT;" + ORDERED,
             ("R-31882-08811", "R-45095-63572"), ("constraint-failure", "fail", "transaction")),
        case("insert-or-rollback-in-transaction", KEYS,
             "BEGIN; CREATE TABLE n(x); INSERT INTO n VALUES (1); INSERT OR ROLLBACK INTO k VALUES (2, 'a'); "
             "INSERT INTO n VALUES (2); INSERT INTO k VALUES (3, 'c'); COMMIT;" + ORDERED,
             ("R-31881-13880",), ("constraint-failure", "rollback", "transaction")),
        case("column-on-conflict-rollback", "CREATE TABLE r(v UNIQUE ON CONFLICT ROLLBACK, w); INSERT INTO r VALUES ('a', 1);",
             "BEGIN; INSERT INTO r VALUES ('b', 2); INSERT INTO r VALUES ('a', 3); SELECT v, w FROM r ORDER BY v; COMMIT;",
             ("R-34093-09213", "R-31881-13880"), ("constraint-failure", "rollback", "column-conflict", "transaction")),
        case("or-rollback-in-autocommit", KEYS,
             "INSERT INTO k VALUES (2, 'b'); INSERT OR ROLLBACK INTO k VALUES (3, 'c'), (4, 'a');" + ORDERED,
             ("R-42089-41020",), ("constraint-failure", "rollback", "autocommit")),
        case("raise-abort-in-transaction", raised("ABORT"),
             "BEGIN; INSERT INTO t VALUES (1); INSERT INTO t VALUES (2), (-1);" + BOTH + " COMMIT;",
             ("R-62308-64553", "R-47224-48532"), ("trigger", "raise", "abort", "transaction")),
        case("raise-fail-in-transaction", raised("FAIL"),
             "BEGIN; INSERT INTO t VALUES (1); INSERT INTO t VALUES (2), (-1);" + BOTH + " COMMIT;",
             ("R-62308-64553", "R-31882-08811"), ("trigger", "raise", "fail", "transaction")),
        case("raise-rollback-in-transaction", raised("ROLLBACK"),
             "BEGIN; INSERT INTO t VALUES (1); INSERT INTO t VALUES (2), (-1);" + BOTH + " COMMIT;",
             ("R-62308-64553", "R-31881-13880"), ("trigger", "raise", "rollback", "transaction")),
        case("trigger-body-constraint-failure", LOGGED + " INSERT INTO log VALUES (5);",
             "BEGIN; INSERT INTO t VALUES (1); INSERT INTO t VALUES (2), (5);" + BOTH + " COMMIT;" + BOTH,
             ("R-47224-48532",), ("trigger", "constraint-failure", "transaction")),
        case("trigger-body-or-rollback", "CREATE TABLE t(a INTEGER PRIMARY KEY); CREATE TABLE log(x UNIQUE); "
             "CREATE TRIGGER l AFTER INSERT ON t BEGIN INSERT OR ROLLBACK INTO log VALUES (new.a); END; "
             "INSERT INTO log VALUES (5);",
             "BEGIN; INSERT INTO t VALUES (1); INSERT INTO t VALUES (5);" + BOTH + " COMMIT;",
             ("R-57724-61571", "R-31881-13880"), ("trigger", "rollback", "transaction")),
        case("outer-or-rollback-in-trigger", LOGGED + " INSERT INTO log VALUES (5);",
             "BEGIN; INSERT INTO t VALUES (1); INSERT OR ROLLBACK INTO t VALUES (5);" + BOTH + " COMMIT;",
             ("R-35856-58769", "R-31881-13880"), ("trigger", "rollback", "outer-conflict", "transaction")),
        case("transaction-control-errors", KEYS,
             "BEGIN; INSERT INTO k VALUES (2, 'b'); BEGIN; INSERT INTO k VALUES (3, 'c'); COMMIT; COMMIT; "
             "ROLLBACK;" + ORDERED,
             ("R-11576-11990", "R-32090-20403"), ("transaction", "begin", "commit", "rollback")),
        case("failed-unique-index-leaves-the-name", "CREATE TABLE d(x); INSERT INTO d VALUES (1), (1);",
             "CREATE UNIQUE INDEX j ON d(x); INSERT INTO d VALUES (1); CREATE INDEX j ON d(x); "
             "SELECT x FROM d ORDER BY x;",
             ("R-06718-34797",), ("create-index", "constraint-failure")),
        case("failed-add-column-leaves-no-column", KEYS,
             "ALTER TABLE k ADD COLUMN c INTEGER NOT NULL; SELECT c FROM k; "
             "ALTER TABLE k ADD COLUMN c INTEGER DEFAULT 2; SELECT id, c FROM k;",
             ("R-29868-13536",), ("add-column", "prepare-error")),
        case("failed-create-table-leaves-the-name", KEYS,
             "CREATE TABLE p(a, a); INSERT INTO p VALUES (1); CREATE TABLE p(a); INSERT INTO p VALUES (1); "
             "SELECT a FROM p;",
             ("R-44050-47362",), ("create-table", "prepare-error")),
        case("sum-overflow-in-transaction", "CREATE TABLE big(x INTEGER); INSERT INTO big VALUES (9223372036854775807);",
             "BEGIN; INSERT INTO big VALUES (1); SELECT sum(x) FROM big; INSERT INTO big VALUES (2); COMMIT; "
             "SELECT count(*) FROM big;",
             ("R-08904-24719",), ("run-error", "aggregate", "transaction")),
        case("immediate-foreign-key-in-transaction",
             "CREATE TABLE parent(id INTEGER PRIMARY KEY); "
             "CREATE TABLE child(id INTEGER PRIMARY KEY, pid REFERENCES parent(id)); INSERT INTO parent VALUES (1);",
             "BEGIN; INSERT INTO child VALUES (1, 1); INSERT INTO child VALUES (2, 9); INSERT INTO child VALUES (3, 1); "
             "COMMIT; SELECT id, pid FROM child ORDER BY id;",
             ("R-09323-30470", "R-35290-16460"), ("foreign-key", "constraint-failure", "transaction")),
    ]


def records(cases: list[QueryCase] | None = None) -> list[dict[str, Json]]:
    """Record each case natively as a version 6 record, which runs on after an error, in the part
    `after-error` with its features: under SQLite's default measured profile, or under the
    profile with foreign keys on for the cases in `FOREIGN_KEYS`."""
    selected = definitions() if cases is None else cases
    plain, keys = authored_resolution.profile(()), authored_foreign_keys.profile()
    return [{**record_sql(case.setup, case.sql, name=case.name, requirements=list(case.requirements), outputs=True,
                          profile=keys if case.name in FOREIGN_KEYS else plain, run_on=True),
             "part": "after-error", "features": list(case.features)}
            for case in selected]
