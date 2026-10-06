"""Engine time reaches ordinary SQL, column defaults, triggers and read-only probes."""

from pathlib import Path

import pytest

from conformance.native_clock import NativeClock
from conformance.native_connection import Connection, library_path, load_library

pytestmark = [pytest.mark.integration, pytest.mark.conformance, pytest.mark.requires_native("sqlite3")]


def test_engine_clock_defaults_triggers_and_probes(tmp_path: Path) -> None:
    """Changing only the clock changes every engine 'now' read; native VFS stays default."""
    engine = load_library(library_path())
    clock = NativeClock(engine, 1700000000000)
    connection = Connection(engine, tmp_path / "clock.db", vfs=clock.name)
    try:
        connection.execute_script("CREATE TABLE t(stamp DEFAULT(unixepoch()));"
            "CREATE TABLE audit(stamp); CREATE TRIGGER log AFTER INSERT ON t BEGIN "
            "INSERT INTO audit VALUES(unixepoch()); END;")
        for milliseconds in (1700000000000, 1800000000000):
            clock.set_time(milliseconds)
            connection.query("INSERT INTO t DEFAULT VALUES;")
            expected = [(1, milliseconds // 1000)]
            assert list(connection.query("SELECT stamp FROM t ORDER BY rowid DESC LIMIT 1;")[0]) == expected
            assert list(connection.query("SELECT stamp FROM audit ORDER BY rowid DESC LIMIT 1;")[0]) == expected
            assert list(connection.query_result("SELECT unixepoch('now');", readonly=True).rows[0]) == expected
        assert engine.sqlite3_vfs_find(None).contents.zName != clock.vfs.zName
        with pytest.raises(ValueError, match="Unix milliseconds"):
            clock.set_time(True)
    finally:
        connection.close()
        clock.close()
    assert not engine.sqlite3_vfs_find(clock.name)
