"""Versioned SQLite evidence independent of frontend admission or model constructors."""

from contextlib import ExitStack
from dataclasses import replace
from pathlib import Path
from tempfile import TemporaryDirectory

from conformance.case_format import Json
from conformance.native_statements import execute
from conformance.native_connection import Cell, Connection, library_path, load_library
from conformance import native_observation
from conformance.execution_profile import ExecutionProfile
from conformance.native_clock import NativeClock, utc_timezone
from conformance.native_acquisition import open_case
from conformance.native_library import DEFAULT_ENGINE_VERSION, SOURCE_IDS, library_binary
from conformance.native_call_recording import recording_inputs, validate_recording
from conformance.native_bindings import is_read_only_tcl_helper


def record_sql(setup: str | list[str | dict[str, Json]], migration: str, *, name: str, requirements: list[str] | None = None,
               library: Path | None = None, outputs: bool = False,
               parameters: list[tuple[Cell, ...]] | None = None,
               profile: ExecutionProfile | None = None, setup_clock: int | None = None,
               clock_values: list[int] | int | None = None,
               setup_helpers: list[str] | None = None, migration_readonly: bool = False,
               migration_readonly_spans: list[tuple[int, int]] | None = None,
               auxiliary_replay: bool = False, tcl_calls: dict[str, Json] | None = None,
               setup_parameters: list[list[tuple[Cell, ...]]] | None = None,
               parameter_names: list[list[str | None]] | None = None,
               setup_parameter_names: list[list[list[str | None]]] | None = None,
               setup_call_indices: list[int] | None = None,
               source_setup_commands: list[str | dict[str, Json]] | None = None,
               temporary_root: Path | None = None, fixture_paths: list[Path] | None = None) -> dict[str, Json]:
    """Keep exact call inputs and native evidence with fixed or per-statement clocks.

    An explicit root places ordinary file fixtures there; an optional path list
    records their actual database paths without adding them to native evidence.
    """
    if parameters is not None and not outputs:
        raise ValueError("Bound parameters require output recording")
    setup, recording, setup_calls = recording_inputs(setup, migration, tcl_calls, setup_parameters,
        setup_call_indices, source_setup_commands, outputs, setup_parameter_names, parameter_names)
    if setup_calls is not None:
        setup_helpers = [call["helper"] if call is not None else "eval" for call in setup_calls]
    controlled = profile is not None and profile.clock == "unix-milliseconds-v1"
    auxiliary_replay = auxiliary_replay or any(helper.startswith("aux:") for helper in setup_helpers or [])
    if tcl_calls is not None:
        auxiliary_replay = auxiliary_replay or any(call["helper"].startswith("aux:") for call in tcl_calls["assertion"])
    if recording is not None:
        recording.update(setupHelpers=setup_helpers or ["eval"] * len(setup),
            migrationReadonly=migration_readonly, migrationReadonlySpans=[list(span) for span in migration_readonly_spans or []],
            auxiliaryReplay=auxiliary_replay)
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
                    events = list(execute(writer, command, outputs=recording is not None,
                        parameters=setup_parameters[index] if setup_parameters is not None else None,
                        parameter_names=setup_parameter_names[index] if setup_parameter_names is not None else None,
                        record_bindings=recording is not None,
                        tcl_calls=[setup_calls[index]] if setup_calls is not None else None,
                        select_only=is_read_only_tcl_helper(helper)))
                if recording is not None:
                    recording["setupBindings"].append([{key: event[key] for key in ("parameterNames", "parameters")}
                                                       for event in events])
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
            visible = native_observation.observe(writer)
            return {"visible": visible, "persisted": native_observation.observe(reader) if writer.transaction_open else visible,
                    "transactionOpen": writer.transaction_open}

        initial = snapshot()
        trace = [{**event, **snapshot()} for event in execute(writer, migration, outputs=outputs,
            parameters=parameters, clock=clock, clock_values=clock_values,
            transaction_mode=profile.transaction_mode if profile else None, select_only=migration_readonly,
            readonly_spans=migration_readonly_spans, committed_reads=auxiliary_replay,
            record_bindings=recording is not None, parameter_names=parameter_names,
            tcl_calls=tcl_calls["assertion"] if tcl_calls is not None else None)]
    result = {"nativeVersion": 4 if profile is not None else 3 if outputs else 2 if isinstance(setup, list) and any(isinstance(item, dict) for item in setup) else 1, "name": name, "setupSql": setup if isinstance(setup, str) else "\n".join(item for item in setup if isinstance(item, str)),
            "setupCommands": [setup] if isinstance(setup, str) else setup, "setupOutcomes": setup_outcomes,
            "setupResults": setup_results, "setupErrors": setup_errors, "migrationSql": migration,
            "sourceId": engine.sqlite3_sourceid().decode(), "requirements": requirements or [], "initial": initial, "trace": trace,
            **({"profile": profile.to_wire(), "setupClockUnixMilliseconds": setup_clock} if profile else {}), **(recording or {})}
    validate_recording(result)
    return result
