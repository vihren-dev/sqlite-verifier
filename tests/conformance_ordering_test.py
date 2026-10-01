"""Native sort equality and full boundary groups retain result multiplicity."""

from pathlib import Path

import pytest

from conformance.native_connection import Connection, library_path, load_library
from conformance.native_ordering import tie_groups

pytestmark = [pytest.mark.integration, pytest.mark.conformance, pytest.mark.requires_native("sqlite3")]


def test_native_ties_and_window_boundaries(tmp_path: Path) -> None:
    """INTEGER/REAL and NOCASE ties follow SQLite; both boundaries retain all eligible rows."""
    connection = Connection(load_library(library_path()), tmp_path / "ordering.db")
    try:
        connection.execute_script("CREATE TABLE t(k,v); INSERT INTO t VALUES"
            "(NULL,'null'),(1,'integer'),(1.0,'real'),(2,'middle'),(3,'a'),(3,'b');")
        rows = connection.query_result("SELECT k,v FROM t ORDER BY k;", readonly=True).rows
        groups = tie_groups(connection, rows, (0,), ("BINARY",))
        assert [group["count"] for group in groups] == [1, 2, 1, 2]
        cut = tie_groups(connection, rows, (0,), ("BINARY",), offset=2, limit=3)
        assert [group["count"] for group in cut] == [1, 1, 1]
        assert [len(group["rows"]) for group in cut] == [2, 1, 2]
        one = tie_groups(connection, rows, (0,), ("BINARY",), offset=1, limit=1)
        assert len(one) == 1 and one[0]["count"] == 1 and len(one[0]["rows"]) == 2
        assert tie_groups(connection, rows, (), (), offset=2, limit=2)[0]["count"] == 2
        assert len(tie_groups(connection, rows, (), ())[0]["rows"]) == 6
        assert tie_groups(connection, rows, (0,), ("BINARY",), limit=0) == []
        connection.execute_script("CREATE TABLE words(x); INSERT INTO words VALUES('a'),('A'),('b');")
        words = connection.query_result("SELECT DISTINCT x FROM words ORDER BY x COLLATE NOCASE DESC;",
                                        readonly=True).rows
        assert [group["count"] for group in tie_groups(connection, words, (0,), ("NOCASE",))] == [1, 2]
        assert connection.query("SELECT count(*) FROM words;") == [((1, 3),)]
        with pytest.raises(ValueError, match="not observable"):
            tie_groups(connection, words, (0,), ("unknown",))
    finally:
        connection.close()
