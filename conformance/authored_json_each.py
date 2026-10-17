"""Authored coverage cases of `json_each` in FROM (ADR 0012, amendment 5, slice 6d).

The cases follow the "Tests" list of the slice 6d task: `json_each` alone, after a table
with a correlated argument, as an inner join with `ON`, and twice with aliases; `*`, the
hidden columns, qualified and ambiguous names; `WHERE`, `ORDER BY`, aggregates and
`GROUP BY` over its columns; arrays, objects, scalars, a path, a missing path and a NULL
argument; node positions with JSONB headers of one, two and three bytes; and the prepare
error of too many arguments. Native SQLite is the only source of outcomes. The pinned
documentation has no page of `json_each`, so the cases name the requirements of joins in
`lang_select.html` and of JSON extraction in `lang_expr.html`. The cases use
`conformance.authored_queries.QueryCase` and its recorder.
"""

from conformance.authored_queries import QueryCase, records as query_records
from conformance.case_format import Json

TABLES = ("CREATE TABLE t(id INTEGER, j TEXT); INSERT INTO t VALUES(1, '[1,2]'); "
          "INSERT INTO t VALUES(2, '{\"k\":\"v\",\"n\":3}'); INSERT INTO t VALUES(3, NULL); "
          "CREATE TABLE k(key TEXT); INSERT INTO k VALUES('x');")
"""Rows of JSON text and NULL for the correlated cases, and a table with a column `key`."""

JSON = "R-52226-38079"
"""SQLite: the JSON functions perform JSON subcomponent extraction."""
PRODUCT = "R-44414-54710"
"""SQLite: a join has a row for each combination of a left and a right row."""
ON = "R-38465-03616"
"""SQLite: the ON expression is evaluated for each row of the cartesian product."""
ORDER = "R-59089-25828"
"""SQLite: the columns of a join are the left columns followed by the right columns."""


def definitions() -> list[QueryCase]:
    """The coverage cases of `json_each` in FROM."""
    case = QueryCase
    return [
        case("each-array", TABLES, "SELECT * FROM json_each('[10,{\"x\":1},30]');", (JSON,), ("json-each", "array")),
        case("each-object", TABLES,
             "SELECT * FROM json_each('{\"a\":1,\"b\":[2,3],\"c\":\"s\",\"d\":null,\"e\":true,\"f\":2.5,\"a b\":0}');",
             (JSON,), ("json-each", "object")),
        case("each-scalar", TABLES, "SELECT * FROM json_each('7');", (JSON,), ("json-each", "scalar")),
        case("each-path", TABLES,
             "SELECT key, value, id, fullkey, path FROM json_each('{\"a\":{\"b\":[1,2]}}', '$.a.b');",
             (JSON,), ("json-each", "path")),
        case("each-no-rows", TABLES,
             "SELECT count(*) FROM json_each('[1]', '$.x'); SELECT count(*) FROM json_each(NULL); "
             "SELECT count(*) FROM json_each('[]');", (JSON,), ("json-each", "no-rows")),
        case("each-hidden-columns", TABLES, "SELECT z.*, z.json, root FROM json_each('[1]', '$') AS z;", (JSON, ORDER),
             ("json-each", "hidden")),
        case("each-correlated", TABLES, "SELECT t.id, e.key, e.value FROM t, json_each(t.j) AS e;",
             (JSON, PRODUCT, ORDER), ("json-each", "correlated")),
        case("each-join-on", TABLES, "SELECT t.id, e.value FROM t JOIN json_each(t.j) e ON e.type = 'integer';",
             (JSON, ON), ("json-each", "join", "on")),
        case("each-twice", TABLES, "SELECT a.value, b.value FROM json_each('[1,2]') a, json_each('[3,4]') AS b;",
             (JSON, PRODUCT, ORDER), ("json-each", "join")),
        case("each-where-order", TABLES, "SELECT value FROM json_each('[3,1,2]') WHERE value > 1 ORDER BY value;",
             (JSON,), ("json-each", "where", "order-by")),
        case("each-group-by", TABLES, "SELECT type, count(*) FROM json_each('[1,\"a\",2,null]') GROUP BY type;",
             (JSON,), ("json-each", "group-by")),
        case("each-qualified-name", TABLES, "SELECT json_each.key, k.key FROM k, json_each('[1]');", (JSON,),
             ("json-each", "names")),
        case("each-ambiguous-name", TABLES, "SELECT key FROM k, json_each('[1]');", (JSON,),
             ("json-each", "names", "prepare-error")),
        case("each-too-many-arguments", TABLES, "SELECT * FROM json_each('[1]', '$', 3);", (JSON,),
             ("json-each", "prepare-error")),
        case("each-header-sizes", TABLES,
             "SELECT key, id FROM json_each('[\"" + "a" * 12 + "\",\"" + "b" * 300 + "\",1]');", (JSON,),
             ("json-each", "node-positions")),
        case("each-json5", TABLES, "SELECT key, value, type, fullkey FROM json_each('{a:0x10, b:.5, \"c d\":[1,],}');",
             (JSON,), ("json-each", "json5")),
    ]


def records(cases: list[QueryCase] | None = None) -> list[dict[str, Json]]:
    """Record each case natively as a version 5 record with outputs, in the part `json-each`."""
    return query_records(definitions() if cases is None else cases, part="json-each")
