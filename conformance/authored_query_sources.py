"""Native inputs for derived SELECT sources (ADR 0019, D5 and D3).

The cases exercise all output columns, source scope, joins, metadata and uncertain
membership. SQLite supplies every outcome through the existing query recorder.
The uncertain-membership and fallible-source cases deliberately remain unmodeled.
"""

from conformance.authored_queries import QueryCase, records as query_records
from conformance.authored_subqueries import COLUMN_TYPE, CORRELATED, SUBQUERY
from conformance.case_format import Json

TABLES = (
    "CREATE TABLE t(a TEXT COLLATE NOCASE, b INTEGER, c); "
    "INSERT INTO t VALUES('a',1,'1'),('B',2,'2'),('a',3,'3'); "
    "CREATE TABLE u(a TEXT, b INTEGER); INSERT INTO u VALUES('A',1),('z',4); "
    "CREATE TABLE e(a TEXT, b INTEGER);"
)
"""Typed and untyped columns, case-folding neighbors, unmatched rows and an empty table."""


def definitions() -> list[QueryCase]:
    """The observable derived-source cases, including refusal boundaries and prepare errors."""
    def case(name: str, sql: str, *features: str) -> QueryCase:
        """Give a source case the common schema and the relevant SQLite source requirements."""
        requirements = (SUBQUERY, COLUMN_TYPE) + ((CORRELATED,) if "outer" in features else ())
        return QueryCase("source-" + name, TABLES, sql, requirements, ("derived-source", *features))

    return [
        case("columns", "SELECT d.* FROM (SELECT a,b,c FROM t) d ORDER BY b;", "star", "qualification"),
        case("nested", "SELECT y FROM (SELECT x AS y FROM (SELECT b AS x FROM t)) ORDER BY y;", "nested"),
        case("all-metadata", "SELECT a = 'A', b = '1', c = 1 FROM (SELECT a,b,c FROM t) WHERE b=1;",
             "affinity", "collation", "multiple-columns"),
        case("explicit-collation", "SELECT a='A', b='A' FROM (SELECT a COLLATE BINARY AS a, a COLLATE NOCASE AS b FROM t) WHERE a='a';",
             "collation", "explicit"),
        case("literal-affinity", "SELECT x='1', y='1', z=1 FROM (SELECT 1 AS x, CAST(1 AS INTEGER) AS y, CAST(1 AS TEXT) AS z);",
             "affinity", "cast"),
        case("duplicate-names", 'SELECT * FROM (SELECT 1 AS x,2 AS x,3 AS "x:1",4 AS X);', "names", "duplicates"),
        case("aliased-rowid", "SELECT d.rowid FROM (SELECT b AS rowid FROM t) d ORDER BY rowid;", "rowid", "alias"),
        case("no-implicit-rowid", "SELECT rowid FROM (SELECT b FROM t);", "rowid", "error"),
        case("anonymous-qualification", 'SELECT "".x FROM (SELECT 1 AS x);', "qualification", "error"),
        case("inner-join", "SELECT d.a,d.b,u.a,u.b FROM (SELECT a,b FROM t) d JOIN u ON d.b=u.b;", "join"),
        case("left-join", "SELECT d.a AS da,d.b AS db,u.a AS ua,u.b AS ub FROM (SELECT a,b FROM t) d LEFT JOIN u ON d.b=u.b ORDER BY db;", "left", "null-extension"),
        case("right-join", "SELECT t.a AS ta,t.b AS tb,d.a AS da,d.b AS db FROM t RIGHT JOIN (SELECT a,b FROM u) d ON t.b=d.b ORDER BY db;", "right", "null-extension"),
        case("full-join", "SELECT d.a,d.b,u.a,u.b FROM (SELECT a,b FROM t) d FULL JOIN u ON d.b=u.b;", "full", "null-extension"),
        case("using-collation", "SELECT a,b FROM (SELECT a,b FROM t) JOIN (SELECT a FROM u) USING(a) ORDER BY b;", "using", "collation"),
        case("natural", "SELECT * FROM (SELECT a,b FROM t) NATURAL JOIN (SELECT a FROM u) ORDER BY b;", "natural", "collation"),
        case("nested-using", "SELECT (SELECT count(*) FROM (SELECT 'a' COLLATE NOCASE AS x) JOIN (SELECT 'A' AS x) USING(x));", "using", "nested"),
        case("full-output-collation", "SELECT a='A',a FROM (SELECT a FROM t WHERE b=1) FULL JOIN (SELECT a FROM u WHERE b=1) USING(a);", "full", "collation"),
        case("empty-join", "SELECT d.a AS da,u.a AS ua,u.b AS ub FROM (SELECT a FROM e) d RIGHT JOIN u ON 1 ORDER BY ub;", "empty", "right"),
        case("outer-binding", "SELECT b,(SELECT x FROM (SELECT t.b AS x)) FROM t ORDER BY b;", "outer", "correlated"),
        case("outer-depth", "SELECT b,(SELECT (SELECT x FROM (SELECT t.b AS x))) FROM t ORDER BY b;", "outer", "nested"),
        case("sibling-refused", "SELECT * FROM t,(SELECT t.b);", "scope", "error"),
        case("own-name-shadows", "SELECT b,(SELECT b FROM (SELECT 9 AS b)) FROM t ORDER BY b;", "scope", "shadowing"),
        case("scalar-and-in", "SELECT b,(SELECT b+1),b IN (SELECT b FROM u) FROM (SELECT b FROM t) ORDER BY b;", "scalar", "in"),
        case("aggregate", "SELECT n,s FROM (SELECT count(*) AS n,sum(b) AS s FROM t);", "aggregate"),
        case("distinct", "SELECT a FROM (SELECT DISTINCT a FROM t) ORDER BY a;", "distinct"),
        case("compound-columns", "SELECT a,b FROM (SELECT a COLLATE BINARY AS a,b FROM t UNION SELECT a,b FROM u) ORDER BY b,a;", "compound", "multiple-columns"),
        case("compound-representative-uncertain", "SELECT a,b FROM (SELECT a,b FROM t UNION SELECT a,b FROM u);", "compound", "unmodeled"),
        case("compound-affinity", "SELECT x=1,y='1' FROM (SELECT CAST('1' AS TEXT) AS x,CAST(1 AS INTEGER) AS y UNION ALL SELECT 1,'1');", "compound", "affinity"),
        case("compound-left-collation", "SELECT a='A' FROM (SELECT a FROM t WHERE b=1 UNION ALL SELECT a FROM u WHERE 0);", "compound", "collation"),
        case("d3-in-collation", "SELECT 'A' IN (SELECT a FROM t WHERE b=1 UNION SELECT a FROM u WHERE 0 ORDER BY 1 COLLATE BINARY);", "d3", "in", "collation"),
        case("d3-scalar-collation", "SELECT (SELECT a FROM t WHERE b=1 UNION SELECT a FROM u WHERE 0 ORDER BY 1 COLLATE BINARY)='A';", "d3", "scalar", "collation"),
        case("d3-in-affinity", "SELECT '1' IN (SELECT CAST(1 AS INTEGER) UNION SELECT 2 ORDER BY 1 COLLATE BINARY);", "d3", "in", "affinity"),
        case("limit-ordered", "SELECT b FROM (SELECT b FROM t ORDER BY b LIMIT 1 OFFSET 1);", "limit", "offset"),
        case("limit-zero", "SELECT * FROM (SELECT a,b FROM t LIMIT 0);", "limit", "empty"),
        case("limit-all", "SELECT b FROM (SELECT b FROM t LIMIT 10);", "limit", "certain"),
        case("limit-equal-rows", "SELECT a FROM (SELECT a FROM t WHERE b<>2 LIMIT 1);", "limit", "certain"),
        case("limit-uncertain", "SELECT b FROM (SELECT b FROM t LIMIT 1);", "limit", "unmodeled"),
        case("limit-second-column-uncertain", "SELECT x,y FROM (SELECT 1 AS x,b AS y FROM t LIMIT 1);", "limit", "multiple-columns", "unmodeled"),
        case("fallible", "SELECT * FROM (SELECT abs(-9223372036854775808) AS x);", "failure", "unmodeled"),
        case("missing-table-first", "SELECT * FROM (SELECT missing FROM t),absent;", "error", "precedence"),
        case("source-body-order", "SELECT * FROM (SELECT first),(SELECT second);", "error", "precedence"),
        case("scalar-body-order", "SELECT (SELECT first),(SELECT second),missing;", "error", "precedence"),
    ]


def records(cases: list[QueryCase] | None = None) -> list[dict[str, Json]]:
    """Record each input with the pinned native SQLite and ordinary query-output bindings."""
    return query_records(definitions() if cases is None else cases, part="query-sources")
