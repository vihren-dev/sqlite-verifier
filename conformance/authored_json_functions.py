"""Authored coverage cases of `json_type`, `json_valid`, `json_array_length` and `json`
(ADR 0012, amendment 5, slice 6c).

The cases follow the "Tests" list of the slice 6c task: each type name and the type of
numbers; `json_valid` of JSON, JSON5 and malformed text under each kind of flags, and the
flags error; array lengths; `json` of white space, JSON5, escapes and duplicate keys; the
errors of slice 6b; a wrong number of arguments; and the functions in `WHERE`, `SET` and
`VALUES` and over a table column. A JSON failure is part of a case only where the model
describes it: in a query without `FROM`. Native SQLite is the only source of outcomes. The
pinned documentation has no page of the JSON functions, so the cases name the requirement
of `lang_expr.html` that the extract functions perform JSON subcomponent extraction. The
cases use `conformance.authored_queries.QueryCase` and its recorder.
"""

from conformance.authored_queries import QueryCase, records as query_records
from conformance.case_format import Json

TABLES = ("CREATE TABLE d(j TEXT); INSERT INTO d VALUES('{\"a\":[1,2]}'); INSERT INTO d VALUES('{a:2}'); "
          "INSERT INTO d VALUES('x');")
"""A table of strict JSON, JSON5 and malformed text, for the cases over a column and with writes."""

JSON = "R-52226-38079"
"""SQLite: the default JSON functions perform JSON subcomponent extraction."""


def definitions() -> list[QueryCase]:
    """The coverage cases of the further JSON functions."""
    case = QueryCase
    return [
        case("json-type-names", TABLES,
             "SELECT json_type('{\"a\":1}'), json_type('[1,2.5,\"x\",true,false,null,[]]', '$[0]'), "
             "json_type('[1,2.5]', '$[1]'), json_type('[\"x\"]', '$[0]'), json_type('[true,false]', '$[0]'), "
             "json_type('[true,false]', '$[1]'), json_type('[null]', '$[0]'), json_type('[[]]', '$[0]');",
             (JSON,), ("json", "type")),
        case("json-type-numbers", TABLES,
             "SELECT json_type('9223372036854775808'), json_type('0x1F'), json_type('1e400'), json_type(12), "
             "json_type(1.5);", (JSON,), ("json", "type", "numbers")),
        case("json-type-null", TABLES,
             "SELECT json_type('{\"a\":1}', '$.b'), json_type(NULL), json_type('[1]', NULL);", (JSON,),
             ("json", "type", "null")),
        case("json-valid-strict", TABLES,
             "SELECT json_valid('{\"a\":1}'), json_valid('{a:1}'), json_valid('[1,]'), json_valid('/*c*/1'), "
             "json_valid('{bad'), json_valid(''), json_valid(12), json_valid(NULL);", (JSON,), ("json", "valid")),
        case("json-valid-flags", TABLES,
             "SELECT json_valid('{a:1}', 2), json_valid('{a:1}', 1), json_valid('[1]', 4), json_valid('[1]', 5), "
             "json_valid('{a:1}', '2'), json_valid('[1]', 15.9), json_valid('[1]', '1e2');", (JSON,),
             ("json", "valid", "flags")),
        case("json-valid-flags-error", TABLES, "SELECT json_valid('[1]', 0);", (JSON,), ("json", "valid", "error")),
        case("json-valid-flags-null", TABLES, "SELECT json_valid(NULL, NULL);", (JSON,),
             ("json", "valid", "error")),
        case("json-array-length", TABLES,
             "SELECT json_array_length('[1,2,3]'), json_array_length('{\"a\":1}'), json_array_length('1'), "
             "json_array_length('[]'), json_array_length('{\"a\":[1,2]}', '$.a'), json_array_length('[1]', '$.x');",
             (JSON,), ("json", "array-length")),
        case("json-minify", TABLES,
             "SELECT json(' { \"a\" : [1, 2.50, \"x\\u0041\"] } '), json('{a:0x1F, b:.5,}'), "
             "json('{\"a\":1,\"a\":2}'), json('[Infinity,NaN,-0,1E400]'), json(NULL), json(12);", (JSON,),
             ("json", "minify")),
        case("json-type-malformed", TABLES, "SELECT json_type('{bad');", (JSON,), ("json", "type", "error")),
        case("json-array-length-bad-path", TABLES, "SELECT json_array_length('[1]', 'x');", (JSON,),
             ("json", "array-length", "error")),
        case("json-minify-malformed", TABLES, "SELECT json('{bad');", (JSON,), ("json", "minify", "error")),
        case("json-type-argument-count", TABLES, "SELECT json_type('[1]', '$', '$');", (JSON,),
             ("json", "type", "prepare-error")),
        case("json-minify-argument-count", TABLES, "SELECT json('[1]', 1);", (JSON,),
             ("json", "minify", "prepare-error")),
        case("json-valid-over-column", TABLES, "SELECT j, json_valid(j), json_valid(j, 2) FROM d;", (JSON,),
             ("json", "valid", "column")),
        case("json-functions-in-where", TABLES,
             "SELECT json_type(j), json_array_length(j, '$.a'), json(j) FROM d WHERE json_valid(j, 2) = 1;",
             (JSON,), ("json", "column", "where")),
        case("json-minify-in-set", TABLES, "UPDATE d SET j = json(j) WHERE json_valid(j, 2) = 1;", (JSON,),
             ("json", "set")),
        case("json-functions-in-values", TABLES,
             "INSERT INTO d VALUES(json_type('[1]')); INSERT INTO d VALUES(json_valid('x'));", (JSON,),
             ("json", "values-row")),
    ]


def records(cases: list[QueryCase] | None = None) -> list[dict[str, Json]]:
    """Record each case natively as a version 5 record with outputs, in the part `json-functions`."""
    return query_records(definitions() if cases is None else cases, part="json-functions")
