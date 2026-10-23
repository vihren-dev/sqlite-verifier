"""Authored coverage cases of compound SELECT (ADR 0019, slice 3; plans/20261023-compound-select.task.md).

The cases follow the "Tests" list of the task: each operator as a statement, chains with mixed
operators, NULLs, the collation sources of outcome 2, `EXCEPT` and `INTERSECT` under a
collation, `ORDER BY` by number and by a name of the first term, `LIMIT` with and without
`ORDER BY`, the prepare errors of outcomes 4, 5 and 7, and the guide's form that compares two
tables. `conformance.authored_compound_subqueries` has the compound subqueries of outcome 9, the
`ORDER BY` by an alias of a later term and by an expression, and the term failures of outcome 10.
Native SQLite is the only source of outcomes. The cases use
`conformance.authored_queries.QueryCase` and its recorder.

The recorder ranks the rows of an `ORDER BY` or `LIMIT` statement again over the derived table
of the statement (`conformance.native_ordering.query_groups`). It takes only numbers and result
names as keys, sorts under the collations of the derived table's columns, and refuses a nested
`LIMIT`, and it runs the statement again without its `LIMIT`. So a statement case orders by a
number or a name of the first term, under the collation of the first term; a subquery case has
no `LIMIT`; and no case has a term failure that a `LIMIT` prevents.
"""

from conformance.authored_queries import QueryCase, records as query_records
from conformance.case_format import Json

TABLES = ("CREATE TABLE t(a TEXT, n TEXT COLLATE NOCASE); INSERT INTO t VALUES('1', 'a'), ('2', 'b'), (NULL, NULL); "
          "CREATE TABLE u(b INTEGER, m TEXT); INSERT INTO u VALUES(1, 'A'), (2, 'b'), (2, 'b'), (NULL, NULL); "
          "CREATE TABLE v(a TEXT, n TEXT COLLATE NOCASE); INSERT INTO v VALUES('1', 'a'), ('3', 'c'); "
          "CREATE TABLE w(n TEXT COLLATE NOCASE); INSERT INTO w VALUES('C'), ('a'); CREATE TABLE e(x);")
"""Tables with NULL rows: `t` with a TEXT column and a NOCASE column, `u` with an INTEGER column
and a TEXT column without collation, a repeated row and values that equal those of `t` only
under NOCASE or with affinity; `v` with the columns of `t` and other rows; `w` with two NOCASE
values whose BINARY order is not their NOCASE order; and an empty table."""

COMPOUND_COUNT = "R-39368-64333"
"""SQLite: all the SELECTs of a compound return the same number of result columns."""
UNION_ALL = "R-55918-19023"
"""SQLite: UNION ALL returns all the rows of the left SELECT and all the rows of the right SELECT."""
UNION = "R-20560-39162"
"""SQLite: UNION is UNION ALL with the duplicate rows removed."""
INTERSECT = "R-45764-31737"
"""SQLite: INTERSECT returns the intersection of the results of the left and right SELECTs."""
EXCEPT = "R-25787-28949"
"""SQLite: EXCEPT returns the rows of the left SELECT that the right SELECT does not return."""
DISTINCT_RESULT = "R-40729-56447"
"""SQLite: INTERSECT and EXCEPT remove duplicate rows from their results."""
LEFT_TO_RIGHT = "R-32562-20566"
"""SQLite: three or more SELECTs group from left to right."""
NULL_EQUAL = "R-46765-43362"
"""SQLite: for duplicate rows of a compound, NULL equals NULL and differs from every other value."""
NO_AFFINITY = "R-32706-07403"
"""SQLite: no affinity applies to the values that a compound compares."""
COMPOUND_COLLATION = "R-51232-50224"
"""SQLite: a compound compares text as the operands of `=` compare it, without the precedence of `COLLATE`."""
ORDER_ALL = "R-34494-34867"
"""SQLite: the ORDER BY of a compound applies to all its elements."""
ORDER_NUMBER = "R-29779-04281"
"""SQLite: an ORDER BY constant integer K is an alias for the K-th result column."""
ORDER_LEFT_MOST = "R-44130-32593"
"""SQLite: an ORDER BY term that is no integer alias is searched for in the left-most SELECT first."""
ORDER_COLLATE = "R-64199-22471"
"""SQLite: an ORDER BY term with a postfix COLLATE sorts under that collation."""
ORDER_EXACT = "R-28853-08147"
"""SQLite: an ORDER BY term of a compound that is no alias equals a result expression exactly."""
LIMIT_ALL = "R-03782-50113"
"""SQLite: the LIMIT of a compound applies to the entire compound."""
LIMIT_NEGATIVE = "R-03014-26414"
"""SQLite: a negative LIMIT gives no upper bound on the rows."""


def definitions() -> list[QueryCase]:
    """The coverage cases of compound SELECT: the statements of this module, then the subqueries
    and term failures of `conformance.authored_compound_subqueries`."""
    from conformance.authored_compound_subqueries import subquery_definitions
    return statement_definitions() + subquery_definitions()


def statement_definitions() -> list[QueryCase]:
    """The coverage cases of compound statements: operators, equal rows, collations, ORDER BY and
    LIMIT, and the prepare errors."""
    case = QueryCase
    return [
        case("compound-union-all", TABLES, "SELECT b FROM u UNION ALL SELECT a FROM t;", (UNION_ALL,),
             ("compound", "union-all")),
        case("compound-union", TABLES, "SELECT b FROM u UNION SELECT a FROM t ORDER BY 1;", (UNION, ORDER_ALL),
             ("compound", "union")),
        case("compound-intersect", TABLES, "SELECT b FROM u INTERSECT SELECT CAST(a AS INTEGER) FROM t;",
             (INTERSECT, DISTINCT_RESULT, NULL_EQUAL), ("compound", "intersect")),
        case("compound-except", TABLES, "SELECT m FROM u EXCEPT SELECT n FROM t;", (EXCEPT, DISTINCT_RESULT,
             COMPOUND_COLLATION), ("compound", "except", "collation")),
        case("compound-chains", TABLES,
             "SELECT 1 UNION SELECT 2 INTERSECT SELECT 2; SELECT 1 UNION ALL SELECT 1 EXCEPT SELECT 2; "
             "SELECT 3 EXCEPT SELECT 3 UNION SELECT 4; SELECT 1 INTERSECT SELECT 1 UNION ALL SELECT 1;",
             (LEFT_TO_RIGHT, UNION, INTERSECT, EXCEPT, UNION_ALL), ("compound", "chain")),
        case("compound-nulls", TABLES,
             "SELECT NULL EXCEPT SELECT NULL; SELECT 1, NULL INTERSECT SELECT 1, NULL; SELECT NULL UNION SELECT NULL; "
             "SELECT b, m FROM u EXCEPT SELECT NULL, NULL;",
             (NULL_EQUAL,), ("compound", "null")),
        case("compound-no-affinity", TABLES,
             "SELECT 1 INTERSECT SELECT '1'; SELECT 1 INTERSECT SELECT 1.0; SELECT b FROM u INTERSECT SELECT a FROM t;",
             (NO_AFFINITY,), ("compound", "affinity")),
        case("compound-collation-column", TABLES,
             "SELECT 'A' EXCEPT SELECT n FROM t; SELECT 'A' INTERSECT SELECT n FROM t; SELECT m FROM u EXCEPT SELECT n FROM t;",
             (COMPOUND_COLLATION,), ("compound", "collation")),
        case("compound-collation-operators", TABLES,
             "SELECT +n FROM t INTERSECT SELECT m FROM u; SELECT CAST(n AS TEXT) FROM t INTERSECT SELECT m FROM u; "
             "SELECT 'A' COLLATE NOCASE EXCEPT SELECT m FROM u;",
             (COMPOUND_COLLATION,), ("compound", "collation")),
        case("compound-collation-none", TABLES,
             "SELECT 'A' || '' EXCEPT SELECT n FROM t; SELECT (SELECT 'A') EXCEPT SELECT n FROM t; "
             "SELECT max(n) FROM t EXCEPT SELECT 'B'; SELECT 'A' EXCEPT SELECT 'a';",
             (COMPOUND_COLLATION,), ("compound", "collation")),
        case("compound-order-by-number-and-name", TABLES,
             "SELECT b AS x, m FROM u UNION SELECT 5, 'z' ORDER BY x DESC, 2; SELECT a FROM t UNION SELECT m FROM u ORDER BY a;",
             (ORDER_NUMBER, ORDER_LEFT_MOST, ORDER_ALL), ("compound", "order-by")),
        case("compound-order-by-collation", TABLES,
             "SELECT n FROM w UNION SELECT 'b' ORDER BY 1; SELECT n FROM w UNION ALL SELECT 'b' ORDER BY n DESC;",
             (ORDER_ALL, COMPOUND_COLLATION), ("compound", "order-by", "collation")),
        case("compound-order-by-collate", TABLES,
             "SELECT 'b' AS x, 1 AS y UNION SELECT n, 1 FROM w ORDER BY y COLLATE BINARY, x; "
             "SELECT n COLLATE NOCASE FROM w EXCEPT SELECT 'c' ORDER BY 1 COLLATE BINARY;",
             (ORDER_COLLATE,), ("compound", "order-by", "collate")),
        case("compound-order-by-integer-forms", TABLES,
             "SELECT (SELECT 1 UNION SELECT 2 ORDER BY 0x1 DESC), (SELECT 3 UNION SELECT 4 ORDER BY (1)), "
             "(SELECT 5 UNION SELECT 6 ORDER BY - -1 DESC);", (ORDER_NUMBER,), ("compound", "order-by")),
        case("compound-limit", TABLES,
             "SELECT b FROM u UNION SELECT a FROM t ORDER BY 1 LIMIT 2 OFFSET 1; SELECT 1 UNION ALL SELECT 2 LIMIT -1;",
             (LIMIT_ALL, LIMIT_NEGATIVE), ("compound", "limit")),
        case("compound-limit-without-order", TABLES,
             "SELECT 1 UNION ALL SELECT 2 LIMIT 1; SELECT b FROM u EXCEPT SELECT 1 LIMIT 1 OFFSET 1;",
             (LIMIT_ALL,), ("compound", "limit", "possible-results")),
        case("compound-terms-with-clauses", TABLES,
             "SELECT b, count(*) FROM u GROUP BY b HAVING count(*) > 1 UNION ALL SELECT DISTINCT a, 0 FROM t "
             "WHERE a IS NOT NULL ORDER BY 1, 2; SELECT t.a, u.m FROM t JOIN u ON u.b = t.a EXCEPT SELECT '2', 'b' ORDER BY 1;",
             (UNION_ALL, EXCEPT), ("compound", "aggregate", "join")),
        case("compound-compare-tables", TABLES,
             "SELECT * FROM t EXCEPT SELECT * FROM v; SELECT * FROM v EXCEPT SELECT * FROM t;", (EXCEPT,),
             ("compound", "except", "guide")),
        case("compound-column-count", TABLES, "SELECT 1 UNION ALL SELECT 1, 2;", (COMPOUND_COUNT,),
             ("compound", "error")),
        case("compound-no-such-table-first", TABLES, "SELECT 1 FROM missing UNION SELECT nosuch FROM t;",
             (COMPOUND_COUNT,), ("compound", "error", "order")),
        case("compound-right-term-first", TABLES, "SELECT nosuch1 UNION SELECT nosuch2;", (COMPOUND_COUNT,),
             ("compound", "error", "order")),
        case("compound-names-before-count", TABLES, "SELECT nosuch1 UNION SELECT 1, 2;", (COMPOUND_COUNT,),
             ("compound", "error", "order")),
        case("compound-count-before-left-names", TABLES, "SELECT nosuch UNION SELECT 1 UNION SELECT 1, 2;",
             (COMPOUND_COUNT,), ("compound", "error", "order")),
        case("compound-count-before-order-by", TABLES, "SELECT 1 UNION SELECT 1, 2 ORDER BY 5;", (COMPOUND_COUNT,),
             ("compound", "error", "order")),
        case("compound-order-by-out-of-range", TABLES, "SELECT 1 UNION SELECT 2 ORDER BY 2;", (ORDER_NUMBER,),
             ("compound", "order-by", "error")),
        case("compound-order-by-no-match", TABLES, "SELECT a FROM t UNION SELECT b FROM u ORDER BY a + 1;",
             (ORDER_EXACT,), ("compound", "order-by", "error")),
        case("compound-order-by-large-integer", TABLES, "SELECT 1 UNION SELECT 2 ORDER BY 2147483648;",
             (ORDER_EXACT,), ("compound", "order-by", "error")),
        case("compound-order-by-real", TABLES, "SELECT 1 UNION SELECT 2 ORDER BY 1.0;", (ORDER_EXACT,),
             ("compound", "order-by", "error")),
        case("compound-order-by-negative", TABLES, "SELECT 1 UNION SELECT 2 ORDER BY -1;", (ORDER_NUMBER,),
             ("compound", "order-by", "error")),
    ]


def records(cases: list[QueryCase] | None = None) -> list[dict[str, Json]]:
    """Record each case natively as a version 5 record with outputs, in the part `compound`."""
    return query_records(definitions() if cases is None else cases, part="compound")
