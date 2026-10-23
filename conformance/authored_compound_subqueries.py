"""Authored coverage cases of compound subqueries and of the terms that SQLite runs (ADR 0019,
slice 3; plans/20261023-compound-select.task.md).

The cases follow the "Tests" list of the task: compound subqueries in `EXISTS`, `IN` and a scalar
subquery with correlation, with the affinity and the collation of the right-most term (outcome
9); `ORDER BY` by an alias of a later term and by an expression in scalar subqueries (outcome 7);
a compound subquery in a write; the prepare errors of a compound subquery; and the failures of
outcome 10 that SQLite skips and that it gives. The tables and requirement identifiers are those
of `conformance.authored_compound`.
"""

from conformance.authored_compound import (COMPOUND_COLLATION, EXCEPT, INTERSECT, LEFT_TO_RIGHT, ORDER_EXACT,
                                           ORDER_LEFT_MOST, TABLES, UNION, UNION_ALL)
from conformance.authored_queries import QueryCase

SCALAR_COMPOUND = "R-56294-03966"
"""SQLite: compound SELECT queries are allowed as scalar subqueries."""
FIRST_ROW = "R-18318-14995"
"""SQLite: the value of a subquery expression is the first row of the result."""
CORRELATED = "R-25616-08788"
"""SQLite: a scalar subquery or the operand of IN or EXISTS may refer to columns of the outer query."""
IN_AFFINITY = "R-24564-50022"
"""SQLite: the right operand of IN has the affinity of the result set expression of its SELECT."""
IN_SCALAR = "R-35033-20570"
"""SQLite: the subquery of IN must be a scalar subquery if the left expression is not a row value."""
EXISTS_ONE = "R-58553-63740"
"""SQLite: EXISTS is 1 if the SELECT would return one or more rows."""
SEPARATE_TERMS = "R-03407-11483"
"""SQLite: each ORDER BY term may match result columns of a different SELECT of the compound."""


def subquery_definitions() -> list[QueryCase]:
    """The coverage cases of compound subqueries and of the terms that SQLite runs."""
    case = QueryCase
    return [
        case("compound-exists-correlated", TABLES,
             "SELECT a FROM t WHERE EXISTS (SELECT 1 FROM u WHERE b = t.a EXCEPT SELECT 1 WHERE t.a = '2') ORDER BY a;",
             (EXISTS_ONE, CORRELATED, EXCEPT), ("compound", "subquery", "exists", "correlated")),
        case("compound-in-right-most-term", TABLES,
             "SELECT '1' IN (SELECT b FROM u WHERE b = 1 UNION SELECT 5), '1' IN (SELECT 5 UNION SELECT b FROM u WHERE b = 1), "
             "'A' IN (SELECT n FROM t UNION SELECT m FROM u WHERE 0), 'A' IN (SELECT m FROM u WHERE 0 UNION SELECT n FROM t);",
             (IN_AFFINITY, UNION), ("compound", "subquery", "in", "affinity", "collation")),
        case("compound-in-correlated", TABLES,
             "SELECT a, n IN (SELECT m FROM u WHERE b = t.a UNION ALL SELECT 'z'), "
             "a IN (SELECT a FROM v INTERSECT SELECT t.a) FROM t ORDER BY a;",
             (CORRELATED, UNION_ALL, INTERSECT), ("compound", "subquery", "in", "correlated")),
        case("compound-scalar-right-most-term", TABLES,
             "SELECT (SELECT b FROM u WHERE b = 1 EXCEPT SELECT 5) = '1', (SELECT 5 WHERE 0 UNION SELECT b FROM u WHERE b = 1) = '1', "
             "(SELECT m FROM u WHERE 0 UNION SELECT n FROM t WHERE n = 'a') = 'A';",
             (SCALAR_COMPOUND, FIRST_ROW, COMPOUND_COLLATION), ("compound", "subquery", "scalar", "affinity")),
        case("compound-scalar-first-row", TABLES,
             "SELECT (SELECT 2 UNION SELECT 1 ORDER BY 1 DESC), a, (SELECT m FROM u WHERE b = t.a UNION SELECT t.n ORDER BY 1) "
             "FROM t ORDER BY a;",
             (SCALAR_COMPOUND, FIRST_ROW, CORRELATED), ("compound", "subquery", "scalar", "order-by")),
        case("compound-scalar-order-by-later-term", TABLES,
             "SELECT (SELECT 1 AS a UNION SELECT 2 AS b ORDER BY b DESC), "
             "(SELECT a FROM t WHERE a IS NOT NULL UNION SELECT lower(m) FROM u WHERE m IS NOT NULL ORDER BY lower(m) DESC);",
             (ORDER_LEFT_MOST, ORDER_EXACT, SEPARATE_TERMS), ("compound", "subquery", "order-by", "alias", "expression")),
        case("compound-subquery-write", TABLES,
             "UPDATE t SET n = (SELECT max(m) FROM u UNION ALL SELECT 'x' WHERE 0) "
             "WHERE EXISTS (SELECT 1 FROM v WHERE v.a = t.a INTERSECT SELECT 1); SELECT a, n FROM t ORDER BY a;",
             (SCALAR_COMPOUND, CORRELATED), ("compound", "subquery", "update")),
        case("compound-subquery-columns", TABLES, "SELECT 1 IN (SELECT 1, 2 UNION SELECT 3, 4);", (IN_SCALAR,),
             ("compound", "subquery", "error")),
        case("compound-name-in-own-term", TABLES, "SELECT 1 FROM u UNION SELECT b;", (UNION,),
             ("compound", "name", "error")),
        case("compound-right-term-skipped", TABLES,
             "SELECT 1 INTERSECT SELECT 2 INTERSECT SELECT abs(-9223372036854775808); "
             "SELECT x FROM e EXCEPT SELECT abs(-9223372036854775808);",
             (LEFT_TO_RIGHT, INTERSECT, EXCEPT), ("compound", "failure", "skipped")),
        case("compound-term-failure", TABLES, "SELECT 1 UNION SELECT abs(-9223372036854775808);", (UNION,),
             ("compound", "failure")),
        case("compound-term-failure-limit", TABLES, "SELECT 1 UNION SELECT abs(-9223372036854775808) LIMIT 1;",
             (UNION,), ("compound", "failure", "limit")),
        case("compound-term-failure-limit-zero", TABLES,
             "SELECT abs(-9223372036854775808) UNION SELECT 1 UNION ALL SELECT 2 LIMIT 0;", (UNION, UNION_ALL),
             ("compound", "failure", "limit")),
    ]
