"""Additional native conditions are measured without reinterpreting frozen profiles."""

from dataclasses import replace
from itertools import product
from pathlib import Path

import pytest

from conformance.execution_profile import measured_profile, profile_from_wire
from conformance.native_connection import Connection, NativeError, library_path, load_library
from conformance.native_library import SOURCE_IDS

pytestmark = [pytest.mark.integration, pytest.mark.conformance,
              pytest.mark.requires_native("sqlite3", "sqlite3-3.53.4")]


@pytest.mark.parametrize("trusted,dml,ddl,readonly", list(product((False, True), repeat=4)))
def test_explicit_native_conditions(tmp_path: Path, trusted: bool, dml: bool,
                                    ddl: bool, readonly: bool) -> None:
    """Each condition is established and read back, with both DQS modes exercised separately."""
    engine = load_library(library_path("sqlite3-3.53.4"), "3.53.4")
    path = tmp_path / "conditions.db"
    fixture = Connection(engine, path)
    try:
        profile = measured_profile(fixture, name="conditions", version=7, format_version=2,
            trusted_schema=trusted, dqs_dml=dml, dqs_ddl=ddl,
            access_mode="read-only" if readonly else "read-write")
        assert profile.source_id == SOURCE_IDS["3.53.4"] and profile.compile_options
        assert profile_from_wire(profile.to_wire()) == profile
        replace(profile, access_mode="read-write").establish(fixture)
        fixture.execute_script("CREATE TABLE t(v); INSERT INTO t VALUES(41);")
        if ddl:
            fixture.execute_script('CREATE TABLE quoted(v CHECK(v != "literal"));')
        else:
            with pytest.raises(NativeError) as denied:
                fixture.execute_script('CREATE TABLE quoted(v CHECK(v != "literal"));')
            assert denied.value.code & 255 == 1
    finally:
        fixture.close()
    connection = Connection(engine, path, access_mode=profile.access_mode)
    try:
        profile.establish(connection)
        assert connection.query('SELECT "v" FROM t;') == [((1, 41),)]
        if dml:
            assert connection.query('SELECT "literal";') == [((3, b"literal"),)]
        else:
            with pytest.raises(NativeError) as denied:
                connection.query('SELECT "literal";')
            assert denied.value.code & 255 == 1
        profile.verify_settings(connection)
        assert connection.is_sql_error(8) is readonly
        assert all(not connection.is_sql_error(code) for code in (264, 520, 776, 1032, 1288, 1544, 10, 14, 5, 7, 13))
        connection.configure(1013, int(not dml))
        with pytest.raises(ValueError, match="DQS setting readback"):
            profile.verify_settings(connection)
        connection.configure(1013, int(dml))
        connection.execute_script(f"PRAGMA trusted_schema={int(not trusted)};")
        with pytest.raises(ValueError, match="setting readback"):
            profile.verify_settings(connection)
    finally:
        connection.close()


def test_transport_and_access_refuse_reinterpretation(tmp_path: Path) -> None:
    """Old profile bytes round trip exactly; format/identity versions and real access stay distinct."""
    import json
    legacy_wire = json.loads((Path(__file__).resolve().parents[1] /
                              "conformance/synthetic-workload/profile.json").read_text())
    legacy = profile_from_wire(legacy_wire)
    assert legacy.to_wire() == legacy_wire and legacy.format_version == 1
    with pytest.raises(ValueError, match="unsupported execution profile"):
        replace(legacy, trusted_schema=False)
    profile = replace(legacy, name="explicit", version=9, format_version=2,
                      trusted_schema=False, dqs_dml=False, access_mode="read-only")
    assert profile_from_wire(profile.to_wire()) == profile
    for damage in ({"formatVersion": True}, {"formatVersion": 1}, {"formatVersion": 3},
                   {"version": True}, {"trustedSchema": 0}, {"dqsDml": 1},
                   {"dqsDdl": "false"}, {"accessMode": "query-only"}):
        with pytest.raises(ValueError, match="execution profile"):
            profile_from_wire({**profile.to_wire(), **damage})
    for field in ("formatVersion", "dqsDdl", "accessMode"):
        wire = profile.to_wire()
        del wire[field]
        with pytest.raises(ValueError, match="execution profile"):
            profile_from_wire(wire)
    engine = load_library(library_path())
    connection = Connection(engine, tmp_path / "access.db")
    try:
        with pytest.raises(ValueError, match="access mode readback"):
            profile.establish(connection)
        with pytest.raises(ValueError, match="engine identity"):
            replace(legacy, source_id="wrong").establish(connection)
        assert not connection.is_sql_error(8)
    finally:
        connection.close()
    with pytest.raises(NativeError) as missing:
        Connection(engine, tmp_path / "missing.db", access_mode="read-only")
    assert missing.value.code & 255 == 14
    with pytest.raises(ValueError, match="access mode"):
        Connection(engine, tmp_path / "access.db", access_mode="query-only")


def test_trusted_schema_off_preserves_native_clock_and_cascades(tmp_path: Path) -> None:
    """The native VFS clock leaves built-in default/trigger safety intact under trusted schema off."""
    from conformance.corpus import native_replay
    from conformance.native_record import record_sql
    engine = load_library(library_path("sqlite3-3.53.4"), "3.53.4")
    connection = Connection(engine, tmp_path / "measure.db")
    try:
        profile = measured_profile(connection, name="clock-safe", format_version=2,
            trusted_schema=False, dqs_dml=False, dqs_ddl=False,
            foreign_keys=True, clock="unix-milliseconds-v1")
    finally:
        connection.close()
    setup = ("CREATE TABLE p(id PRIMARY KEY,stamp DEFAULT(unixepoch()));"
        "CREATE TABLE c(id REFERENCES p(id) ON DELETE CASCADE); CREATE TABLE audit(stamp);"
        "CREATE TRIGGER log AFTER INSERT ON p BEGIN INSERT INTO audit VALUES(unixepoch()); END;")
    evidence = record_sql(setup, "INSERT INTO p(id) VALUES(1); INSERT INTO c VALUES(1);"
        "SELECT stamp FROM audit; DELETE FROM p; SELECT * FROM c;", name="clock-safe",
        outputs=True, profile=profile, setup_clock=0, clock_values=1700000000000)
    assert evidence["trace"][2]["rows"] == [[{"integer": {"value": 1700000000}}]]
    assert evidence["trace"][-1]["rows"] == []
    native_replay([evidence])
