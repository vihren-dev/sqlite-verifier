"""Authored coverage cases of literal defaults with the writes of ADR 0012 (slice 6e1).

Draft #130 adds literal column defaults: an omitted INSERT value takes the column's
default, stored with the column's affinity, and ADD COLUMN gives existing rows the
default. Slice 6e1 brings it into the stack, so these cases combine an omitted value with
the forms that slices 5a to 5d added: a rowid alias, a unique key, `NOT NULL`, an
`ON CONFLICT` clause, `INSERT OR` and `RETURNING`, and an added column with a query
without FROM and a JSON function. Native SQLite is the only source of outcomes. The cases
use `conformance.authored_queries.QueryCase` and its recorder.
"""

from conformance.authored_queries import QueryCase, records as query_records
from conformance.case_format import Json

DEFAULT = "R-12183-43719"
"""SQLite: columns that the column list of INSERT omits take their default value."""
LITERAL = "R-12572-62501"
"""SQLite: a constant NULL, text, blob or signed-number default is used directly."""


def definitions() -> list[QueryCase]:
    """The coverage cases of literal defaults with the writes of the stack."""
    case = QueryCase
    return [
        case("default-rowid-alias", "CREATE TABLE t(id INTEGER PRIMARY KEY, a TEXT DEFAULT 'x', b);",
             "INSERT INTO t(b) VALUES(1); INSERT INTO t(id, b) VALUES(5, 2); SELECT id, a, b FROM t ORDER BY id;",
             (DEFAULT,), ("default", "rowid-alias")),
        case("default-affinity", "CREATE TABLE t(a INTEGER DEFAULT '12', b TEXT DEFAULT 3, c);",
             "INSERT INTO t(c) VALUES(1); SELECT a, b FROM t;", (DEFAULT, LITERAL),
             ("default", "affinity")),
        case("default-not-null", "CREATE TABLE t(a TEXT NOT NULL DEFAULT 'z', b);",
             "INSERT INTO t(b) VALUES(1); SELECT a, b FROM t;", (DEFAULT,), ("default", "not-null")),
        case("default-unique-conflict", "CREATE TABLE t(k INTEGER UNIQUE DEFAULT 7, v);",
             "INSERT INTO t(v) VALUES(1); INSERT INTO t(v) VALUES(2);", (DEFAULT,), ("default", "unique")),
        case("default-on-conflict", "CREATE TABLE t(k INTEGER UNIQUE DEFAULT 7, v);",
             "INSERT INTO t(v) VALUES(1); INSERT INTO t(v) VALUES(2) ON CONFLICT(k) DO UPDATE SET v = excluded.v; "
             "SELECT k, v FROM t;", (DEFAULT,), ("default", "upsert")),
        case("default-insert-or", "CREATE TABLE t(k INTEGER UNIQUE DEFAULT 7, v);",
             "INSERT INTO t(v) VALUES(1); INSERT OR REPLACE INTO t(v) VALUES(2); INSERT OR IGNORE INTO t(v) VALUES(3); "
             "SELECT k, v FROM t;", (DEFAULT,), ("default", "insert-or")),
        case("default-returning", "CREATE TABLE t(a INTEGER DEFAULT 4, b);",
             "INSERT INTO t(b) VALUES(1) RETURNING a, b;", (DEFAULT,), ("default", "returning")),
        case("default-added-column", "CREATE TABLE t(a); INSERT INTO t VALUES(1);",
             "ALTER TABLE t ADD COLUMN c INTEGER DEFAULT 3; SELECT a, c FROM t; SELECT json_type(c) FROM t;",
             (DEFAULT,), ("default", "add-column")),
    ]


def records(cases: list[QueryCase] | None = None) -> list[dict[str, Json]]:
    """Record each case natively as a version 5 record with outputs, in the part `default-writes`."""
    return query_records(definitions() if cases is None else cases, part="default-writes")
