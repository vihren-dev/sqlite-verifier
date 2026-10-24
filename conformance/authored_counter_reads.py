"""Authored cases of the reads of the connection counters (ADR 0024, D2) and of the schema
positions that refuse them.

The cases call `changes()`, `total_changes()` and `last_insert_rowid()` in the expressions of
queries, INSERT, UPDATE and DELETE (with `RETURNING`), where the model describes them, and in the
positions of the schema that refuse a non-deterministic function (SQLite's error, then the
statements that follow). The recorder refuses `random()` and `randomblob()`, so no case calls them.
The cases use `conformance.authored_queries.QueryCase`.
"""

from conformance.authored_queries import QueryCase
from conformance.counter_sql import READ, VALUES

TABLE = "CREATE TABLE t(a INTEGER PRIMARY KEY, b); INSERT INTO t VALUES (4, 1);"
"""A table with one row, for the cases of the schema positions."""


def definitions() -> list[QueryCase]:
    """The cases of the reads of the counters, and of the schema positions."""
    case = QueryCase
    return [
        case("changes-in-expressions", VALUES,
             "UPDATE r SET n = changes(), m = total_changes(); SELECT a, n, m FROM r ORDER BY a;"
             " INSERT INTO r(n, m) VALUES (changes(), total_changes()), (changes(), total_changes());"
             " SELECT a, n, m FROM r ORDER BY a;"
             " UPDATE r SET n = -1 WHERE a <= changes() RETURNING a, changes(), total_changes();"
             " DELETE FROM r WHERE a = changes() RETURNING a, changes(), total_changes();"
             " SELECT a, n, m FROM r ORDER BY a;",
             ("R-58361-29089", "R-38914-26427", "R-43399-09409"), ("counters", "read", "update", "insert")),
        case("last-insert-rowid-in-update-and-delete", VALUES + " INSERT INTO r VALUES (7, 0, 0);",
             "UPDATE r SET n = last_insert_rowid() WHERE a < 3 RETURNING a, n, last_insert_rowid(); "
             "DELETE FROM r WHERE a = last_insert_rowid() RETURNING a, last_insert_rowid(); SELECT a, n FROM r ORDER BY a;",
             ("R-14875-52970", "R-46934-63022"), ("counters", "read", "update", "delete")),
        case("reads-in-queries", VALUES + " UPDATE r SET n = 1 WHERE a = 2;",
             "SELECT changes(), total_changes(), last_insert_rowid() FROM r; "
             "SELECT count(*), changes() FROM r WHERE a > changes() - 5; "
             "SELECT a, total_changes() + 1 AS t, abs(last_insert_rowid()) FROM r ORDER BY a; "
             "SELECT max(last_insert_rowid()), sum(total_changes()) FROM r;",
             ("R-58361-29089", "R-38914-26427", "R-14875-52970"), ("counters", "read", "query")),
        case("counter-functions-in-schema-positions", TABLE,
             "CREATE TABLE g1(a, b AS (changes())); CREATE TABLE g2(a, b AS (total_changes() + a)); "
             "CREATE TABLE g3(a, b AS (last_insert_rowid())); "
             "CREATE INDEX i1 ON t(changes()); CREATE INDEX i2 ON t(a + total_changes()); "
             "CREATE INDEX i3 ON t(abs(last_insert_rowid())); "
             "CREATE INDEX j1 ON t(a) WHERE changes() > 0; CREATE INDEX j2 ON t(a) WHERE total_changes() = a; "
             "CREATE INDEX j3 ON t(a) WHERE last_insert_rowid() > 0; "
             "CREATE TABLE g1(a); CREATE INDEX i1 ON t(b); CREATE INDEX j1 ON t(a);" + READ,
             ("R-55246-25452", "R-45034-43967", "R-60806-29331"), ("counters", "schema-position", "prepare-error")),
    ]
