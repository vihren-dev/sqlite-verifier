"""Native per-statement traces with persistent visible and independent committed views."""

from contextlib import ExitStack
from dataclasses import dataclass
from functools import lru_cache
from pathlib import Path
from tempfile import TemporaryDirectory

from belay.sqlite.sql_model import Table
from belay.sqlite.admission import admit
from belay.sqlite.errors import SqlError
from belay.sqlite.sql_tree import SqlParser, parse
from belay.sqlite.translate import starting_schema, statements
from conformance.native_metadata import check_metadata, identifier, integer, quoted, text
from conformance.case_format import Json, schema_wire, statement_wire, table_wire
from conformance.native_connection import Cell, Connection, NativeError, SQL_ERRORS, SOURCE_ID, library_path, load_library


@dataclass(frozen=True)
class Fixture:
    """Initial rows are independent typed data; setup SQL is not the tested migration."""
    schema_sql: str
    migration_sql: str
    rows: dict[str, list[tuple[int, tuple[Cell, ...]]]]
    name: str


@lru_cache(maxsize=128)
def read_schema(parser: SqlParser, sql: str) -> tuple[Table, ...]:
    """Reuse immutable declarations across cases; the key is the exact SQL and the loaded
    library and grammar, never native observations."""
    return starting_schema(parse(parser, sql.encode(), "conformance-schema.sql"))


def snapshot(connection: Connection, parser: SqlParser,
             cache: dict[str, tuple[Table, ...]] | None = None) -> list[Json]:
    """Read all supported objects and chunk wide rows below the fixed result-column limit."""
    metadata = connection.query("SELECT type,name,sql FROM sqlite_schema ORDER BY name;")
    declarations: list[str] = []
    for kind, name, sql in metadata:
        if text(kind) not in ("table", "index"):
            raise ValueError(f"Unsupported native schema object: {text(name)}")
        if sql[0] != 5:  # Implicit constraint indexes are represented in the table definition.
            declarations.append(text(sql) + ";")
    cache = {} if cache is None else cache
    key = "\n".join(declarations)
    try:
        if key not in cache:
            cache[key] = read_schema(parser, key)
        schema = cache[key]
    except SqlError as error:
        raise ValueError(f"Cannot observe native schema: {error}") from error
    if sorted(table.name for table in schema) != sorted(identifier(name) for kind, name, _ in metadata if text(kind) == "table"):
        raise ValueError("Native table inventory differs from parsed declaration")
    tables: list[Json] = []
    for table in sorted(schema, key=lambda entry: entry.name):
        check_metadata(connection, table)
        rowids = [integer(row[0]) for row in connection.query(
            f"SELECT rowid FROM {quoted(table.name)} ORDER BY rowid;")]
        cells: dict[int, list[Cell]] = {rowid: [] for rowid in rowids}
        for offset in range(0, len(table.columns), 1999):
            names = ",".join(quoted(col.name) for col in table.columns[offset:offset + 1999])
            rows = connection.query(f"SELECT rowid,{names} FROM {quoted(table.name)} ORDER BY rowid;")
            if [integer(row[0]) for row in rows] != rowids:
                raise ValueError("Rows changed while observing a native snapshot")
            for row in rows:
                cells[integer(row[0])].extend(row[1:])
        tables.append([table.name, table_wire(table, [(rowid, tuple(cells[rowid])) for rowid in rowids])])
    return tables


def initialize(connection: Connection, schema: tuple[Table, ...], fixture: Fixture) -> None:
    """Use explicit rowids only for setup, then observe before executing the migration."""
    if set(fixture.rows) - {table.name for table in schema}:
        raise ValueError("Fixture rows name an absent table")
    connection.execute_script(fixture.schema_sql)
    for table in schema:
        names = ",".join(["rowid", *(quoted(column.name) for column in table.columns)])
        for rowid, cells in fixture.rows.get(table.name, []):
            if not -(2**63) <= rowid < 2**63 or len(cells) != len(table.columns):
                raise ValueError("Invalid fixture rowid/width")
            values = ",".join("?" for _ in range(len(cells) + 1))
            connection.query(f"INSERT INTO {quoted(table.name)}({names}) VALUES({values});", ((1, rowid), *cells))


def record(fixture: Fixture, parser: SqlParser, library: Path | None = None, *, migration_coverage: bool = False) -> dict[str, Json]:
    """Acquire real evidence; admission failures are raised before native execution."""
    schema = read_schema(parser, fixture.schema_sql)
    script = statements(parse(parser, fixture.migration_sql.encode(), "migration.sql"))
    admit(schema, script)  # Includes production schema and literal-write admission.
    pinned = load_library(library or library_path())
    if migration_coverage:
        for name in ("__gcov_reset", "__gcov_dump"):
            function = getattr(pinned, name)
            function.argtypes, function.restype = [], None
    with TemporaryDirectory(prefix="conformance-") as directory, ExitStack() as stack:
        database = Path(directory) / "case.db"
        writer = Connection(pinned, database)
        stack.callback(writer.close)
        initialize(writer, schema, fixture)
        reader = Connection(pinned, database)
        stack.callback(reader.close)

        schema_cache: dict[str, tuple[Table, ...]] = {}

        def observe(code: int) -> dict[str, Json]:
            """No observation failure can produce an agreement candidate."""
            visible = snapshot(writer, parser, schema_cache)
            persisted = snapshot(reader, parser, schema_cache) if writer.transaction_open else visible
            return {"visible": visible, "persisted": persisted,
                    "transactionOpen": writer.transaction_open,
                    "primaryCode": code & 255, "extendedCode": code}

        observations: list[Json] = [observe(0)]
        native_error = ""
        sql_bytes = fixture.migration_sql.encode()
        for statement in script:
            code = 0
            if migration_coverage:
                pinned.__gcov_reset()
            try:
                writer.query(sql_bytes[statement.start:statement.end].decode())
            except NativeError as error:
                if error.code & 255 not in SQL_ERRORS:
                    raise
                code = error.code
                native_error = str(error)
            finally:
                if migration_coverage:
                    pinned.__gcov_dump()
                    pinned.__gcov_reset()
            observations.append(observe(code))
            if code:
                break
    if migration_coverage:
        pinned.__gcov_reset()  # Discard final observation/connection cleanup before the exit dump.
    return {"version": 1, "schemaSql": fixture.schema_sql, "migrationSql": fixture.migration_sql,
            "schema": [schema_wire(table) for table in schema],
            "initial": [[table.name, table_wire(table, fixture.rows.get(table.name, []))] for table in schema],
            "script": [statement_wire(statement) for statement in script], "nativeTrace": observations,
            "requirements": [], "provenance": [["fixture", fixture.name], ["sourceId", SOURCE_ID],
                                                ["nativeError", native_error]]}
