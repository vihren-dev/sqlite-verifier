"""Authored coverage cases of queries without FROM (ADR 0012, amendment 5, slice 6a).

The cases follow the "Tests" list of the slice 6a task: a query without `FROM` with a
true, false and NULL `WHERE`; aggregates with and without rows; `GROUP BY`, `ORDER BY`,
`LIMIT` and `OFFSET`; `*` and column names, which are prepare errors; the expressions of
slice 2 without a table; and a query without `FROM` between writes and in a
transaction. Native SQLite is the only source of outcomes. The cases use
`conformance.authored_queries.QueryCase` and its recorder.
"""

from conformance.authored_queries import QueryCase, records as query_records
from conformance.case_format import Json

TABLES = "CREATE TABLE t(a INTEGER); INSERT INTO t VALUES(1);"
"""One table, which the queries without FROM do not read, for the cases with writes."""

NO_FROM = "R-16074-54196"
"""SQLite: without FROM, the input of a simple SELECT is one row of zero columns."""


def definitions() -> list[QueryCase]:
    """The coverage cases of queries without FROM."""
    case = QueryCase
    return [
        case("fromless-values", TABLES, "SELECT 1 + 2, 'x', NULL, 2.5, -7;", (NO_FROM,), ("fromless",)),
        case("fromless-where-true", TABLES, "SELECT 1 WHERE 1 = 1;", (NO_FROM,), ("fromless", "where")),
        case("fromless-where-false", TABLES, "SELECT 1 WHERE 1 = 0;", (NO_FROM,), ("fromless", "where")),
        case("fromless-where-null", TABLES, "SELECT 1 WHERE NULL = 1;", (NO_FROM,), ("fromless", "where")),
        case("fromless-count", TABLES, "SELECT count(*);", (NO_FROM,), ("fromless", "aggregate")),
        case("fromless-count-no-row", TABLES, "SELECT count(*) WHERE 1 = 0;", (NO_FROM,), ("fromless", "aggregate")),
        case("fromless-aggregates", TABLES, "SELECT sum(1), max(2), min(3), avg(4), count(5);", (NO_FROM,),
             ("fromless", "aggregate")),
        case("fromless-aggregates-no-row", TABLES, "SELECT sum(1), max(2), avg(4) WHERE 1 = 0;", (NO_FROM,),
             ("fromless", "aggregate")),
        case("fromless-group-by", TABLES, "SELECT 1 GROUP BY 1;", (NO_FROM,), ("fromless", "group-by")),
        case("fromless-order-limit", TABLES, "SELECT 1 AS x ORDER BY x DESC LIMIT 1;", (NO_FROM,),
             ("fromless", "order-by", "limit")),
        case("fromless-limit-zero", TABLES, "SELECT 1 LIMIT 0;", (NO_FROM,), ("fromless", "limit")),
        case("fromless-offset", TABLES, "SELECT 1 LIMIT 1 OFFSET 1;", (NO_FROM,), ("fromless", "limit")),
        case("fromless-star", TABLES, "SELECT *;", (NO_FROM,), ("fromless", "prepare-error")),
        case("fromless-column", TABLES, "SELECT a;", (NO_FROM,), ("fromless", "prepare-error")),
        case("fromless-qualified", TABLES, "SELECT t.a;", (NO_FROM,), ("fromless", "prepare-error")),
        case("fromless-integer-overflow", TABLES, "SELECT 9223372036854775807 + 1;", (NO_FROM,),
             ("fromless", "arithmetic")),
        case("fromless-division", TABLES, "SELECT 1 / 0, 5 % 0, 7 / 2, 7.0 / 2;", (NO_FROM,),
             ("fromless", "arithmetic")),
        case("fromless-cast", TABLES, "SELECT CAST('12abc' AS INTEGER), CAST(1 AS TEXT), CAST('1.5' AS REAL);",
             (NO_FROM,), ("fromless", "cast")),
        case("fromless-coalesce", TABLES, "SELECT COALESCE(NULL, NULL, 3);", (NO_FROM,), ("fromless", "coalesce")),
        case("fromless-comparisons", TABLES, "SELECT 1 < 2, 'a' = 'A', NULL IS NULL, 1 = 1.0;", (NO_FROM,),
             ("fromless", "comparison")),
        case("fromless-between-writes", TABLES,
             "INSERT INTO t VALUES(2); SELECT 2 * 3; INSERT INTO t VALUES(3);", (NO_FROM,), ("fromless", "writes")),
        case("fromless-transaction", TABLES, "BEGIN; SELECT 1; INSERT INTO t VALUES(4); COMMIT;", (NO_FROM,),
             ("fromless", "transaction")),
    ]


def records(cases: list[QueryCase] | None = None) -> list[dict[str, Json]]:
    """Record each case natively as a version 5 record with outputs, in the part `fromless`."""
    return query_records(definitions() if cases is None else cases, part="fromless")
