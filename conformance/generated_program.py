"""Structural statements rendered to SQL and checked by the production frontend."""

from dataclasses import dataclass, field
from pathlib import Path

from conformance.case_format import Json, statement_wire
from conformance.native_trace import Fixture
from conformance.native_connection import Cell
from belay.sqlite.sql_model import Affinity, Column, Statement
from belay.sqlite.sql_tree import SqlParser, parse
from belay.sqlite.sql_values import SqlValue
from belay.sqlite.translate import statements


def literal(value: SqlValue) -> str:
    """Render only the structural literal domain; boundary probes have separate native records."""
    if value is None:
        return "NULL"
    if isinstance(value, bytes):
        return "X'" + value.hex() + "'"
    return str(value) if isinstance(value, int) else "'" + value.replace("'", "''") + "'"


def command(kind: str, table: str = "", *, column: str = "v", value: SqlValue = None,
            key: int = 1, affinity: Affinity = "blob") -> tuple[Statement, str]:
    """Generate constructors before syntax, independent of the parser under test."""
    statement = Statement(kind, table, (), "generated.sql", 0, 0)
    if kind in ("beginTransaction", "commit", "rollback"):
        return statement, {"beginTransaction": "BEGIN;", "commit": "COMMIT;", "rollback": "ROLLBACK;"}[kind]
    if kind in ("createTable", "addColumn"):
        columns = (Column(column, affinity),)
        statement = Statement(kind, table, columns, "generated.sql", 0, 0)
        sql = f"CREATE TABLE {table}({column} {affinity.upper()});" if kind == "createTable" else f"ALTER TABLE {table} ADD {column} {affinity.upper()};"
    elif kind == "insert":
        statement = Statement(kind, table, (), "generated.sql", 0, 0, ("id", "v"), (key, value))
        sql = f"INSERT INTO {table}(id,v) VALUES({literal(key)},{literal(value)});"
    else:
        statement = Statement(kind, table, (), "generated.sql", 0, 0, (column,), (value,), "id", key)
        sql = f"UPDATE {table} SET {column}={literal(value)} WHERE id={key};"
    return statement, sql


@dataclass
class Program:
    """Keep the expected structural constructors beside their independently rendered SQL."""
    commands: list[tuple[Statement, str]] = field(default_factory=list)
    schema: str = "CREATE TABLE t(id INTEGER NOT NULL,v BLOB,UNIQUE(id));"

    rows: dict[str, list[tuple[int, tuple[Cell, ...]]]] = field(default_factory=lambda: {"t": [(1, ((1, 1), (4, b"")))]})

    def fixture(self) -> Fixture:
        """Start with one valid key and a byte-exact empty BLOB cell."""
        return Fixture(self.schema, "\n".join(sql for _, sql in self.commands),
                       self.rows, "hypothesis")

    def roundtrip(self, parser: SqlParser) -> None:
        """Reject parser/renderer disagreement before native comparison can mask it."""
        parsed = statements(parse(parser, self.fixture().migration_sql.encode(), "generated.sql"))
        assert [statement_wire(item) for item in parsed] == [statement_wire(item) for item, _ in self.commands]


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
            old, new = dict(before["visible"])[name], dict(after["visible"])[name]
            assert len(new["rows"]) == len(old["rows"])
            for first, second in zip(old["rows"], new["rows"], strict=True):
                assert second == {"rowid": first["rowid"], "values": first["values"] + ["null"]}
