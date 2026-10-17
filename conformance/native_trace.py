"""Native per-statement traces with persistent visible and independent committed views.

The case carries the schema and migration as statement syntax; Lean resolves them.
Native tables are read from `sqlite_schema` and their PRAGMA metadata, never from a
Python translation.
"""

from contextlib import ExitStack
from dataclasses import dataclass, field
from pathlib import Path
from tempfile import TemporaryDirectory

from belay.sqlite.sql_tree import SqlParser, parse
from belay.sqlite.syntax import statements
from conformance.case_format import CASE_VERSION, Json, case_profile, row_wire
from conformance.native_connection import Cell, Connection, NativeError, SQL_ERRORS, SOURCE_ID, library_path, load_library
from conformance.native_library import DEFAULT_ENGINE_VERSION
from conformance.native_limits import lower_limits, measured_limits
from conformance.native_metadata import integer, native_table, quoted, table_metadata, text


@dataclass(frozen=True)
class Fixture:
    """Initial rows are independent typed data; setup SQL is not the tested migration.
    `limits` lowers connection limits before the schema runs, for example
    `{"columns": 5}`; the case records the limits that the connection then reports."""
    schema_sql: str
    migration_sql: str
    rows: dict[str, list[tuple[int, tuple[Cell, ...]]]]
    name: str
    limits: dict[str, int] = field(default_factory=dict)


def table_names(connection: Connection) -> list[str]:
    """The names of all tables in `sqlite_schema`; views and triggers are not observed."""
    names: list[str] = []
    for kind, name in connection.query("SELECT type,name FROM sqlite_schema ORDER BY name;"):
        if text(kind) not in ("table", "index"):
            raise ValueError(f"Unsupported native schema object: {text(name)}")
        if text(kind) == "table":
            names.append(text(name))
    return names


def snapshot(connection: Connection) -> list[Json]:
    """Read every table's metadata and rows; chunk wide rows below the connection's
    result-column limit, which a fixture may have lowered."""
    chunk = measured_limits(connection)["columns"] - 1
    tables: list[Json] = []
    for name in table_names(connection):
        info, indexes = table_metadata(connection, name)
        columns = [text(row[1]) for row in info]
        rowids = [integer(row[0]) for row in connection.query(f"SELECT rowid FROM {quoted(name)} ORDER BY rowid;")]
        cells: dict[int, list[Cell]] = {rowid: [] for rowid in rowids}
        for offset in range(0, len(columns), chunk):
            names = ",".join(quoted(column) for column in columns[offset:offset + chunk])
            rows = connection.query(f"SELECT rowid,{names} FROM {quoted(name)} ORDER BY rowid;")
            if [integer(row[0]) for row in rows] != rowids:
                raise ValueError("Rows changed while observing a native snapshot")
            for row in rows:
                cells[integer(row[0])].extend(row[1:])
        tables.append(native_table(name, info, indexes, [row_wire(rowid, tuple(cells[rowid])) for rowid in rowids]))
    return tables


def initialize(connection: Connection, fixture: Fixture) -> None:
    """Run the schema, then insert the fixture rows with explicit rowids before the migration."""
    connection.execute_script(fixture.schema_sql)
    present = set(table_names(connection))
    if set(fixture.rows) - present:
        raise ValueError("Fixture rows name an absent table")
    for table, rows in fixture.rows.items():
        columns = [text(row[1]) for row in connection.query(f"PRAGMA table_info({quoted(table)});")]
        names = ",".join(["rowid", *(quoted(column) for column in columns)])
        for rowid, cells in rows:
            if not -(2**63) <= rowid < 2**63 or len(cells) != len(columns):
                raise ValueError("Invalid fixture rowid/width")
            values = ",".join("?" for _ in range(len(cells) + 1))
            connection.query(f"INSERT INTO {quoted(table)}({names}) VALUES({values});", ((1, rowid), *cells))


def requested(tables: list[Json], fixture: Fixture) -> list[Json]:
    """The native tables with the rows that the fixture requested, so the initial-state
    comparison finds a value that SQLite stored differently, such as NaN stored as NULL."""
    return [{**table, "rows": [row_wire(rowid, cells) for rowid, cells in fixture.rows.get(str(table["name"]), [])]}
            for table in tables if isinstance(table, dict)]


def record(fixture: Fixture, parser: SqlParser, library: Path | None = None, *,
           migration_coverage: bool = False) -> dict[str, Json]:
    """Acquire real evidence; syntax without a model constructor is refused before native execution."""
    schema = statements(parse(parser, fixture.schema_sql.encode(), "conformance-schema.sql"))
    script = statements(parse(parser, fixture.migration_sql.encode(), "migration.sql"))
    pinned = load_library(library or library_path())
    if migration_coverage:
        for name in ("__gcov_reset", "__gcov_dump"):
            function = getattr(pinned, name)
            function.argtypes, function.restype = [], None
    with TemporaryDirectory(prefix="conformance-") as directory, ExitStack() as stack:
        database = Path(directory) / "case.db"
        writer = Connection(pinned, database)
        stack.callback(writer.close)
        limits = lower_limits(writer, fixture.limits)
        initialize(writer, fixture)
        reader = Connection(pinned, database)
        stack.callback(reader.close)

        def observe(code: int, phase: str | None = None) -> dict[str, Json]:
            """No observation failure can produce an agreement candidate."""
            visible = snapshot(writer)
            persisted = snapshot(reader) if writer.transaction_open else visible
            return {"visible": visible, "persisted": persisted, "transactionOpen": writer.transaction_open,
                    "primaryCode": code & 255, "extendedCode": code, "phase": phase}

        observations: list[Json] = [observe(0)]
        native_error = ""
        sql_bytes = fixture.migration_sql.encode()
        for statement in script:
            code, phase = 0, None
            if migration_coverage:
                pinned.__gcov_reset()
            try:
                writer.query(sql_bytes[statement.start:statement.end].decode())
            except NativeError as error:
                if error.code & 255 not in SQL_ERRORS:
                    raise
                code, phase = error.code, error.phase
                native_error = str(error)
            finally:
                if migration_coverage:
                    pinned.__gcov_dump()
                    pinned.__gcov_reset()
            observations.append(observe(code, phase))
            if code:
                break
    if migration_coverage:
        pinned.__gcov_reset()  # Discard final observation/connection cleanup before the exit dump.
    return {"version": CASE_VERSION, "profile": case_profile(DEFAULT_ENGINE_VERSION, SOURCE_ID, limits),
            "schemaSql": fixture.schema_sql, "migrationSql": fixture.migration_sql,
            "schema": [item.value for item in schema], "script": [item.value for item in script],
            "initial": requested(observations[0]["visible"], fixture), "nativeTrace": observations,
            "requirements": [], "provenance": [["fixture", fixture.name], ["sourceId", SOURCE_ID],
                                                ["nativeError", native_error]],
            "parameters": [], "outputs": None, "clocks": []}
