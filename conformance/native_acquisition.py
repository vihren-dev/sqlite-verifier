"""Establish a native acquisition connection and deny unrecordable contexts."""

import ctypes as c
from pathlib import Path

from conformance.execution_profile import ExecutionProfile
from conformance.native_connection import Connection


def permits_foreign_key_context(connection: Connection, setting: bytes) -> bool:
    """Permit FK writes during setup or transactions while profile checks remain in force.

    SQLite ignores transaction-local writes. Setup-boundary and per-statement
    readback check that the case still runs with its selected profile.
    """
    return setting == b"foreign_keys" and (connection.recording_setup or connection.transaction_open)


def open_case(engine: c.CDLL, path: Path, *, profile: ExecutionProfile | None,
              vfs: bytes | None, outputs: bool, auxiliary_replay: bool,
              controlled: bool) -> Connection:
    """Use the same validated opening and authorizer for fixtures, reopens and case SQL."""
    connection = Connection(engine, path, vfs=vfs, access_mode=profile.access_mode if profile else "read-write")
    try:
        if profile is not None:
            profile.establish(connection)
        connection.statement_actions: list[int] = []
        connection.recording_setup = True
        def authorize(_context: int, action: int, _a: bytes, function: bytes,
                      _database: bytes, _trigger: bytes) -> int:
            """Deny unrecordable contexts without turning our denial into SQLite evidence."""
            if outputs and _trigger is None:
                connection.statement_actions.append(action)
            nondeterministic = {b"random", b"randomblob", b"current_timestamp", b"current_date", b"current_time",
                b"date", b"time", b"datetime", b"julianday", b"unixepoch", b"strftime", b"timediff"}
            if controlled:
                nondeterministic = {b"random", b"randomblob"}
            if (profile is not None or auxiliary_replay) and action == 19:
                setting_name = (_a or b"").lower()
                metadata = {b"table_info", b"table_xinfo", b"table_list", b"index_list", b"index_info",
                    b"index_xinfo", b"foreign_key_list", b"foreign_key_check", b"compile_options", b"database_list",
                    b"integrity_check", b"quick_check"}
                settings = {b"foreign_keys", b"recursive_triggers", b"trusted_schema", b"writable_schema"}
                ignored = {setting.encode() for setting, _reason in profile.ignored_settings} if profile else set()
                permitted = profile.permits_setting(setting_name.decode(), function) if profile else setting_name in settings and function is None
                if profile is not None and permits_foreign_key_context(connection, setting_name):
                    permitted = True
                if setting_name not in metadata and not permitted and setting_name not in ignored:
                    connection.recording_exclusion = ("SQL changes an established execution profile or uses an unsupported setting: "
                        + setting_name.decode())
                    return 1
            if action == 24 and (not connection.recording_setup or _a != b":memory:"):
                connection.recording_exclusion = "Excluded connection context: external database"
                return 1
            if action == 31 and function in nondeterministic:
                connection.recording_exclusion = "Excluded connection context: nondeterministic function: " + function.decode()
                return 1
            return 0
        connection.authorizer = c.CFUNCTYPE(c.c_int, c.c_void_p, c.c_int,
            c.c_char_p, c.c_char_p, c.c_char_p, c.c_char_p)(authorize)
        connection.check(engine.sqlite3_set_authorizer(connection.handle, connection.authorizer, None))
        return connection
    except Exception:
        connection.close()
        raise
