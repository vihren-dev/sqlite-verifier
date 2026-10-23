"""Where a statement ends in a recording that runs on after an SQL error (native record version 6).

SQLite's prepare tail does not always end at the end of a failed statement: it stops at the
token of a syntax error, and in the middle of the text for some resolution errors (for example
`CREATE TABLE t(a, a, b)`). A recorder that runs on must find the start of the next statement
without the tail, so it takes the shortest prefix that `sqlite3_complete` accepts and that is
not empty. `sqlite3_complete` also accepts an empty statement, such as a lone `;`, which
SQLite's prepare skips; such a prefix belongs to the statement after it. SQLite's prepare
decides which prefix is empty, so the rule follows SQLite's own tokenizer.
"""

import ctypes as c

from conformance.native_connection import Connection


def empty_statement(connection: Connection, prefix: bytes) -> bool:
    """Whether SQLite's prepare of `prefix` gives no statement and no error, as for a text of
    only semicolons, white space and comments. The prepare changes the connection's error
    message, so call it only after the message of a statement is read. The authorizer can mark
    the connection with a recording exclusion during the prepare; the mark of the connection
    before the call is put back, as the prepare is not a statement of the recording."""
    exclusion = getattr(connection, "recording_exclusion", None)
    statement, tail = c.c_void_p(), c.c_char_p()
    try:
        code = connection.library.sqlite3_prepare_v2(connection.handle, prefix, len(prefix), c.byref(statement),
                                                      c.byref(tail))
    finally:
        if statement.value:
            connection.library.sqlite3_finalize(statement)
        connection.recording_exclusion = exclusion
    return code == 0 and not statement.value


def complete_statement(connection: Connection, remaining: bytes) -> bytes:
    """The shortest prefix of `remaining` that ends with a semicolon, that `sqlite3_complete`
    accepts, and that is not empty (`empty_statement`), or all of `remaining` when no prefix is
    such. For a statement that prepares, this is where SQLite's prepare tail ends."""
    end = remaining.find(b";")
    while end != -1:
        prefix = remaining[:end + 1]
        if connection.library.sqlite3_complete(prefix) and not empty_statement(connection, prefix):
            return prefix
        end = remaining.find(b";", end + 1)
    return remaining
