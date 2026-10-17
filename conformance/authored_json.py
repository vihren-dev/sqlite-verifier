"""Authored coverage cases of JSON reading and `json_extract` (ADR 0012, amendment 5,
slice 6b).

The cases follow the "Tests" list of the slice 6b task: each kind of value, each path form,
a missing path, several paths, `->` and `->>` with a path, a label and an integer,
duplicate keys, JSON5 forms and their rendering, escapes, both errors, and `json_extract`
in `WHERE`, `SET` and `VALUES` and over a table column. A JSON failure is part of a case
only where the model describes it: in a query without `FROM`. Native SQLite is the only
source of outcomes. The pinned documentation has no page of the JSON functions, so the
cases name the requirements of the extract operators in `lang_expr.html`. The cases use
`conformance.authored_queries.QueryCase` and its recorder.
"""

from conformance.authored_queries import QueryCase, records as query_records
from conformance.case_format import Json

TABLES = "CREATE TABLE d(j TEXT); INSERT INTO d VALUES('{\"a\":1}'); INSERT INTO d VALUES('{\"a\":2}');"
"""One table of JSON text, for the cases over a column and with writes."""

EXTRACT = "R-52226-38079"
"""SQLite: the default extract functions perform JSON subcomponent extraction."""
OPERATORS = "R-17939-16412"
"""SQLite: the extract operators are a special syntax for the functions `->` and `->>`."""
ANY_TYPE = "R-24392-63621"
"""SQLite: the extract operators can return values of any type."""


def definitions() -> list[QueryCase]:
    """The coverage cases of JSON reading and `json_extract`."""
    case = QueryCase
    return [
        case("json-scalars", TABLES,
             "SELECT json_extract('{\"a\":1,\"b\":2.5,\"c\":\"x\",\"d\":true,\"e\":false,\"f\":null}', '$.a', '$.b') "
             "AS several, json_extract('{\"b\":2.5}', '$.b'), json_extract('{\"c\":\"x\"}', '$.c'), "
             "json_extract('[true,false,null]', '$[0]'), json_extract('[true,false,null]', '$[1]'), "
             "json_extract('[true,false,null]', '$[2]');", (EXTRACT,), ("json", "values")),
        case("json-containers", TABLES,
             "SELECT json_extract('{\"a\" : [1, {\"b\" : 2}] }', '$.a'), json_extract(' [1.50, 1e2] ', '$');",
             (EXTRACT,), ("json", "rendering")),
        case("json-paths", TABLES,
             "SELECT json_extract('[10,20,30]', '$[1]'), json_extract('[10,20,30]', '$[#-1]'), "
             "json_extract('[10,20,30]', '$[#]'), json_extract('{\"a b\":1}', '$.\"a b\"'), "
             "json_extract('{\"a\":{\"b\":[5]}}', '$.a.b[0]');", (EXTRACT,), ("json", "paths")),
        case("json-missing", TABLES,
             "SELECT json_extract('{\"a\":1}', '$.b'), json_extract('[1]', '$[5]'), json_extract('1', '$.a');",
             (EXTRACT,), ("json", "paths")),
        case("json-several-paths", TABLES, "SELECT json_extract('{\"a\":1,\"b\":\"x\"}', '$.a', '$.b', '$.c');",
             (EXTRACT,), ("json", "paths")),
        case("json-arrows", TABLES,
             "SELECT '{\"a\":\"x\"}' -> '$.a', '{\"a\":\"x\"}' ->> '$.a', '{\"a\":[1]}' -> 'a', '[5,6]' ->> 1, "
             "'[5,6]' -> 1;", (OPERATORS, ANY_TYPE), ("json", "operators")),
        case("json-duplicate-keys", TABLES, "SELECT json_extract('{\"a\":1,\"a\":2}', '$.a');", (EXTRACT,),
             ("json", "paths")),
        case("json5-forms", TABLES,
             "SELECT json_extract('{a:0x1F, b:.5, c:+1, d:''s'', /* note */ e:[1,2,],}', '$'), "
             "json_extract('[Infinity, -Infinity, NaN, 5.]', '$');", (EXTRACT,), ("json", "json5")),
        case("json-numbers", TABLES,
             "SELECT json_extract('[9223372036854775807, 9223372036854775808, 1E400, 0.1]', '$[0]'), "
             "json_extract('[9223372036854775808]', '$[0]'), json_extract('[1E400]', '$[0]'), "
             "json_extract('[0.1]', '$[0]');", (EXTRACT,), ("json", "numbers")),
        case("json-escapes", TABLES,
             "SELECT json_extract('{\"a\":\"caf\\u00e9\\n\\\"\"}', '$.a'), json_extract('[\"caf\\u00e9\\n\"]', '$');",
             (EXTRACT,), ("json", "escapes")),
        case("json-argument-types", TABLES,
             "SELECT json_extract(12, '$'), json_extract(1.5, '$'), json_extract(NULL, '$'), "
             "json_extract('[1]', NULL), json_extract('[1]');", (EXTRACT,), ("json", "arguments")),
        case("json-malformed", TABLES, "SELECT json_extract('{bad', '$');", (EXTRACT,), ("json", "error")),
        case("json-bad-path", TABLES, "SELECT json_extract('{\"a\":1}', 'a');", (EXTRACT,), ("json", "error")),
        case("json-error-in-where", TABLES, "SELECT 1 WHERE json_extract('x', '$') = 1;", (EXTRACT,),
             ("json", "error", "where")),
        case("json-error-in-aggregate", TABLES, "SELECT count(json_extract('x', '$')) LIMIT 1 OFFSET 1;",
             (EXTRACT,), ("json", "error", "aggregate")),
        case("json-error-not-evaluated", TABLES, "SELECT json_extract('x', '$') WHERE 1 = 0;", (EXTRACT,),
             ("json", "error", "where")),
        case("json-over-column", TABLES, "SELECT j ->> 'a' AS v FROM d WHERE json_extract(j, '$.a') > 1;",
             (EXTRACT, OPERATORS), ("json", "column", "where")),
        case("json-order-by", TABLES, "SELECT j -> 'a' AS v FROM d ORDER BY v DESC;", (OPERATORS,),
             ("json", "column", "order-by")),
        case("json-set", TABLES, "UPDATE d SET j = json_extract(j, '$.a') WHERE j ->> 'a' = 2;",
             (EXTRACT, OPERATORS), ("json", "set")),
        case("json-values", TABLES, "INSERT INTO d VALUES(json_extract('{\"a\":[1, 2]}', '$.a'));", (EXTRACT,),
             ("json", "values-row")),
        case("json-error-after-write", TABLES, "INSERT INTO d VALUES('x'); SELECT json_extract('x', '$');",
             (EXTRACT,), ("json", "error", "writes")),
    ]


def records(cases: list[QueryCase] | None = None) -> list[dict[str, Json]]:
    """Record each case natively as a version 5 record with outputs, in the part `json`."""
    return query_records(definitions() if cases is None else cases, part="json")
