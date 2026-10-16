"""Generated statements: expected statement syntax beside independently rendered SQL.

The round trip checks the frontend's mapping (`belay.sqlite.syntax`) against the
syntax the generator intended, before native comparison can mask a difference.
"""

from dataclasses import dataclass, field
from typing import Literal

from belay.sqlite.sql_tree import SqlParser, parse
from belay.sqlite.syntax import statements
from conformance.case_format import Json
from conformance.native_connection import Cell
from conformance.native_trace import Fixture

Affinity = Literal["integer", "real", "text", "blob", "numeric"]
"""A declared type name that the generator writes; SQLite derives the affinity from it."""

SqlValue = int | str | bytes | None
"""A literal value that the generator writes in SQL."""


def literal(value: SqlValue) -> str:
    """Render only the structural literal domain; boundary probes have separate native records."""
    if value is None:
        return "NULL"
    if isinstance(value, bytes):
        return "X'" + value.hex() + "'"
    return str(value) if isinstance(value, int) else "'" + value.replace("'", "''") + "'"


def literal_syntax(value: SqlValue) -> Json:
    """The statement syntax of a rendered literal: SQLite parses a negative number as a negation."""
    if value is None:
        return "null"
    if isinstance(value, bytes):
        return {"blob": {"bytes": list(value)}}
    if isinstance(value, str):
        return {"string": {"bytes": list(value.encode())}}
    number: Json = {"numeric": {"text": str(abs(value))}}
    return {"negate": {"operand": number}} if value < 0 else number


def column_syntax(column: str, affinity: Affinity) -> Json:
    """The syntax of a column with a declared type and no constraints."""
    return {"name": column, "declaredType": affinity.upper(), "constraints": []}


def command(kind: str, table: str = "", *, column: str = "v", value: SqlValue = None,
            key: int = 1, affinity: Affinity = "blob") -> tuple[Json, str]:
    """Generate the expected syntax before the SQL, independent of the parser under test."""
    if kind in ("beginTransaction", "commit", "rollback"):
        return ({"beginTransaction": "begin"}.get(kind, kind),
                {"beginTransaction": "BEGIN;", "commit": "COMMIT;", "rollback": "ROLLBACK;"}[kind])
    if kind == "createTable":
        return ({"createTable": {"name": table, "columns": [column_syntax(column, affinity)], "constraints": []}},
                f"CREATE TABLE {table}({column} {affinity.upper()});")
    if kind == "addColumn":
        return ({"addColumn": {"table": table, "column": column_syntax(column, affinity)}},
                f"ALTER TABLE {table} ADD {column} {affinity.upper()};")
    if kind == "insert":
        return ({"insert": {"table": table, "columns": ["id", "v"], "rows": [[literal_syntax(key), literal_syntax(value)]],
                            "conflicts": [], "algorithm": None}},
                f"INSERT INTO {table}(id,v) VALUES({literal(key)},{literal(value)});")
    filter_: Json = {"equals": {"left": {"identifier": {"name": "id", "doubleQuoted": False}},
                                "right": literal_syntax(key)}}
    return ({"update": {"table": table, "assignments": [[column, literal_syntax(value)]], "filter": filter_}},
            f"UPDATE {table} SET {column}={literal(value)} WHERE id={key};")


@dataclass
class Program:
    """Keep the expected statement syntax beside its independently rendered SQL."""
    commands: list[tuple[Json, str]] = field(default_factory=list)
    schema: str = "CREATE TABLE t(id INTEGER NOT NULL,v BLOB,UNIQUE(id));"

    rows: dict[str, list[tuple[int, tuple[Cell, ...]]]] = field(default_factory=lambda: {"t": [(1, ((1, 1), (4, b"")))]})

    def fixture(self) -> Fixture:
        """Start with one valid key and a byte-exact empty BLOB cell."""
        return Fixture(self.schema, "\n".join(sql for _, sql in self.commands),
                       self.rows, "hypothesis")

    def roundtrip(self, parser: SqlParser) -> None:
        """Reject parser/renderer disagreement before native comparison can mask it."""
        parsed = statements(parse(parser, self.fixture().migration_sql.encode(), "generated.sql"))
        assert [item.value for item in parsed] == [syntax for syntax, _ in self.commands]


def table_named(tables: list[Json], name: str) -> dict[str, Json]:
    """The native table with the given name in one observation."""
    return next(table for table in tables if isinstance(table, dict) and table["name"] == name)


def native_laws(case: dict[str, Json]) -> None:
    """Exercise atomic errors, successful rollback and ADD preservation on actual native traces."""
    for statement, before, after in zip(case["script"], case["nativeTrace"], case["nativeTrace"][1:]):
        if after["primaryCode"]:
            assert after["visible"] == before["visible"]
            assert after["persisted"] == before["persisted"]
        elif statement == "rollback":
            assert before["transactionOpen"] and not after["transactionOpen"]
            assert after["visible"] == before["persisted"]
        elif isinstance(statement, dict) and "addColumn" in statement:
            name = statement["addColumn"]["table"]
            old, new = table_named(before["visible"], name), table_named(after["visible"], name)
            assert len(new["rows"]) == len(old["rows"])
            for first, second in zip(old["rows"], new["rows"], strict=True):
                assert second == {"rowid": first["rowid"], "values": first["values"] + ["null"]}
