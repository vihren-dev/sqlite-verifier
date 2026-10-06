"""Versioned SQLite evidence independent of frontend admission or model constructors."""

from contextlib import ExitStack
from dataclasses import replace
from pathlib import Path
from tempfile import TemporaryDirectory

from conformance.case_format import Json
from conformance.native_statements import execute, wire_rows
from conformance.native_connection import Cell, Connection, SOURCE_ID, library_path, load_library
from conformance.native_metadata import integer, quoted, text
from conformance.execution_profile import ExecutionProfile
from conformance.native_clock import NativeClock, utc_timezone
from conformance.native_acquisition import open_case
from conformance.native_library import DEFAULT_ENGINE_VERSION, SOURCE_IDS, library_binary



def observe(connection: Connection) -> dict[str, Json]:
    """Record all schema objects and readable rows without asking the translator."""
    if any(text(row[1]) not in ("main", "temp") for row in connection.query("PRAGMA database_list;")):
        raise ValueError("Excluded connection context: attached database")
    if connection.query("SELECT name FROM sqlite_temp_schema;"):
        raise ValueError("Excluded connection context: temporary schema")
    schema = connection.query("SELECT type,name,tbl_name,sql FROM sqlite_schema ORDER BY type,name;")
    inventory = {text(row[1]): row for row in connection.query("PRAGMA table_list;") if text(row[0]) == "main"}
    tables: list[Json] = []
    for kind, name_cell, _, _ in schema:
        if text(kind) not in ("table", "view"):
            continue
        name = text(name_cell)
        columns = connection.query(f"PRAGMA table_xinfo({quoted(name)});")
        visible = [row for row in columns if integer(row[6]) != 1]
        names = [text(row[1]) for row in visible]
        without_rowid = bool(integer(inventory[name][4]))
        key = [text(row[1]) for row in sorted(visible, key=lambda row: integer(row[5])) if integer(row[5])]
        rowid = next((alias for alias in ("rowid", "_rowid_", "oid")
                      if alias not in {n.lower() for n in names}), None)
        if not without_rowid and text(kind) == "table" and rowid:
            key = [rowid]
        elif text(kind) == "view" or not without_rowid:
            key = names  # No exposed physical identity: retain the complete ordered multiset.
        ordering = ",".join(quoted(n) for n in key)
        identities = connection.query(f"SELECT {ordering} FROM {quoted(name)} ORDER BY {ordering};")
        values: list[list[Cell]] = [[] for _ in identities]
        for offset in range(0, len(names), 2000):
            selected = ",".join(quoted(n) for n in names[offset:offset + 2000])
            chunk = connection.query(f"SELECT {selected} FROM {quoted(name)} ORDER BY {ordering};")
            if len(chunk) != len(identities):
                raise ValueError("Native rows changed during observation")
            for destination, row in zip(values, chunk, strict=True):
                destination.extend(row)
        indexes = connection.query(f"PRAGMA index_list({quoted(name)});")
        tables.append({"name": name, "kind": text(kind), "withoutRowid": without_rowid,
            "columns": wire_rows(columns), "indexes": [
                {"entry": wire_rows([entry])[0], "columns": wire_rows(connection.query(
                    f"PRAGMA index_xinfo({quoted(text(entry[1]))});"))} for entry in indexes],
            "foreignKeys": wire_rows(connection.query(f"PRAGMA foreign_key_list({quoted(name)});")),
            "rowKey": key, "rows": [{"identity": wire_rows([identity])[0], "values": wire_rows([tuple(row)])[0]}
                                     for identity, row in zip(identities, values, strict=True)]})
    return {"schema": wire_rows(schema), "tables": tables}



def record_sql(setup: str | list[str | dict[str, Json]], migration: str, *, name: str, requirements: list[str] | None = None,
               library: Path | None = None, outputs: bool = False,
               parameters: list[tuple[Cell, ...]] | None = None,
               profile: ExecutionProfile | None = None, setup_clock: int | None = None,
               clock_values: list[int] | int | None = None,
               setup_helpers: list[str] | None = None, migration_readonly: bool = False,
               migration_readonly_spans: list[tuple[int, int]] | None = None,
               auxiliary_replay: bool = False, temporary_root: Path | None = None,
               fixture_paths: list[Path] | None = None) -> dict[str, Json]:
    """Keep native evidence with fixed or per-statement clocks.

    An explicit root places ordinary file fixtures there; an optional path list
    records their actual database paths without adding them to native evidence.
    """
    if parameters is not None and not outputs:
        raise ValueError("Bound parameters require output recording")
    controlled = profile is not None and profile.clock == "unix-milliseconds-v1"
    auxiliary_replay = auxiliary_replay or any(helper.startswith("aux:") for helper in setup_helpers or [])
    if profile is not None and not outputs:
        raise ValueError("Explicit profiles require output recording")
    if controlled != (setup_clock is not None and clock_values is not None):
        raise ValueError("Controlled profile requires setup and statement clock inputs")
    if not controlled and (setup_clock is not None or clock_values is not None):
        raise ValueError("Clock inputs require a controlled profile")
    with TemporaryDirectory(prefix="native-corpus-", dir=temporary_root) as directory, ExitStack() as stack:
        if controlled:
            stack.enter_context(utc_timezone())
        version = profile.engine_version if profile else DEFAULT_ENGINE_VERSION
        if version not in SOURCE_IDS:
            raise ValueError("Execution profile engine has no pinned native build")
        engine = load_library(library or library_path(library_binary(version)), version)
        clock = NativeClock(engine, setup_clock) if controlled else None
        if clock is not None:
            stack.callback(clock.close)
        fixture_profile = replace(profile, access_mode="read-write") if profile else None
        def open_writer(selected: ExecutionProfile | None = fixture_profile) -> Connection:
            """Close every connection before the controlled VFS and fixture directory."""
            connection = open_case(engine, Path(directory) / "case.db", profile=selected,
                vfs=clock.name if clock else None, outputs=outputs,
                auxiliary_replay=auxiliary_replay, controlled=controlled)
            stack.callback(connection.close)
            return connection

        writer = open_writer()
        if fixture_paths is not None:
            database = Path(directory) / "case.db"
            if not database.is_file():
                raise ValueError(f'Native file fixture is missing: {database}; check the native recorder')
            fixture_paths.append(database)
        setup_outcomes: list[Json] = []
        setup_results: list[Json] = []
        setup_errors: list[Json] = []
        if isinstance(setup, str):
            writer.execute_script(setup)
        else:
            if setup_helpers is not None and len(setup_helpers) != len(setup):
                raise ValueError("Expected one Tcl helper per setup command")
            for index, command in enumerate(setup):
                if isinstance(command, dict):
                    if command == {"reopen": True}:
                        if fixture_profile is not None:
                            fixture_profile.verify_settings(writer)
                        writer.close()
                        writer = open_writer()
                    elif set(command) == {"dbConfig"}:
                        option, value = command["dbConfig"]
                        expected = {1010: 0, 1013: int(fixture_profile.dqs_dml) if fixture_profile else 1,
                                    1014: int(fixture_profile.dqs_ddl) if fixture_profile else 1,
                                    1017: int(fixture_profile.trusted_schema) if fixture_profile else 1}
                        if expected.get(option) != value:
                            raise ValueError("Configuration outside the native profile")
                        if writer.configure(option, value) != value:
                            raise ValueError("Configuration readback differs")
                    else:
                        raise ValueError("Unknown native setup operation")
                    events = []
                else:
                    helper = setup_helpers[index] if setup_helpers is not None else "eval"
                    if helper.startswith("aux:") and writer.transaction_open:
                        raise ValueError("Auxiliary read cannot be replayed inside a primary transaction")
                    events = list(execute(writer, command, select_only=helper.startswith("aux:") or helper in {"onecolumn", "exists"}))
                setup_outcomes.append(events[-1]["primaryCode"] if events else 0)
                setup_results.append([row for event in events for row in event["rows"]])
                setup_errors.append(events[-1]["error"] if events else "")
        if writer.transaction_open:
            raise ValueError("Corpus setup must end outside a transaction")
        if fixture_profile is not None:
            fixture_profile.verify_settings(writer)
        if profile is not None and profile.access_mode == "read-only":
            writer.close()
            writer = open_writer(profile)
        writer.recording_setup = False
        reader = Connection(engine, Path(directory) / "case.db", vfs=clock.name if clock else None,
                            access_mode=profile.access_mode if profile else "read-write")
        stack.callback(reader.close)
        if profile is not None:
            profile.establish(reader)

        def snapshot() -> dict[str, Json]:
            """Preserve committed observations independently while a transaction is open."""
            if profile is not None:
                profile.verify_settings(writer)
                profile.verify_settings(reader)
            visible = observe(writer)
            return {"visible": visible, "persisted": observe(reader) if writer.transaction_open else visible,
                    "transactionOpen": writer.transaction_open}

        initial = snapshot()
        trace = [{**event, **snapshot()} for event in execute(writer, migration, outputs=outputs,
            parameters=parameters, clock=clock, clock_values=clock_values,
            transaction_mode=profile.transaction_mode if profile else None, select_only=migration_readonly,
            readonly_spans=migration_readonly_spans, committed_reads=auxiliary_replay)]
    return {"nativeVersion": 4 if profile is not None else 3 if outputs else 2 if isinstance(setup, list) and any(isinstance(item, dict) for item in setup) else 1, "name": name, "setupSql": setup if isinstance(setup, str) else "\n".join(item for item in setup if isinstance(item, str)),
            "setupCommands": [setup] if isinstance(setup, str) else setup, "setupOutcomes": setup_outcomes,
            "setupResults": setup_results, "setupErrors": setup_errors, "migrationSql": migration,
            "sourceId": engine.sqlite3_sourceid().decode(), "requirements": requirements or [], "initial": initial, "trace": trace,
            **({"profile": profile.to_wire(), "setupClockUnixMilliseconds": setup_clock} if profile else {})}
