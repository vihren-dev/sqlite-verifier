"""Profiles establish behavioral settings and refuse altered engine identities."""

from dataclasses import replace
from pathlib import Path

import pytest

from conformance.execution_profile import measured_profile
from conformance.native_connection import Connection, library_path, load_library

pytestmark = [pytest.mark.integration, pytest.mark.conformance, pytest.mark.requires_native("sqlite3")]


def test_profile_engine_settings_and_foreign_keys(tmp_path: Path) -> None:
    """Native readback and cascading behavior agree; false engine claims are refused."""
    connection = Connection(load_library(library_path()), tmp_path / "profile.db")
    try:
        profile = measured_profile(connection, name="synthetic-fk", foreign_keys=True,
            recursive_triggers=True, transaction_mode="immediate", clock="unix-milliseconds-v1")
        profile.establish(connection)
        connection.execute_script("CREATE TABLE p(id PRIMARY KEY);"
            "CREATE TABLE child(id REFERENCES p(id) ON DELETE CASCADE);"
            "INSERT INTO p VALUES(1); INSERT INTO child VALUES(1); BEGIN IMMEDIATE;")
        with pytest.raises(ValueError, match="outside a transaction"):
            profile.establish(connection)
        connection.query("DELETE FROM p;")
        assert connection.query("SELECT * FROM child;") == []
        connection.execute_script("COMMIT;")
        for altered in (replace(profile, source_id="wrong"),
                        replace(profile, engine_version="wrong"),
                        replace(profile, compile_options=("WRONG",))):
            with pytest.raises(ValueError, match="engine identity differs"):
                altered.establish(connection)
        for arguments in ({"clock": "ambient"}, {"transaction_mode": "unknown"}, {"version": True}):
            with pytest.raises(ValueError, match="unsupported execution profile"):
                replace(profile, **arguments)
    finally:
        connection.close()
