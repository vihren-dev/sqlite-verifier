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


def test_record_ordered_queries_and_cuts() -> None:
    """Recording obtains native ranks outside DISTINCT and captures complete cut groups."""
    from conformance.native_record import record_sql
    from conformance.corpus import native_replay
    setup = "CREATE TABLE t(k,v); INSERT INTO t VALUES(1,'a'),(1.0,'b'),(2,'c'),(3,'d'),(3,'e');"
    record = record_sql(setup, "SELECT k,v FROM t ORDER BY k LIMIT ? OFFSET ?;",
                        name="two-cuts", outputs=True, parameters=[((1, 3), (1, 1))])
    groups = record["trace"][0]["groups"]
    assert [group["count"] for group in groups] == [1, 1, 1]
    assert [len(group["rows"]) for group in groups] == [2, 1, 2]
    native_replay([record])
    record = record_sql("CREATE TABLE t(x TEXT COLLATE NOCASE); INSERT INTO t VALUES('a'),('A'),('b');",
                        "SELECT DISTINCT x COLLATE BINARY AS x FROM t ORDER BY x COLLATE NOCASE DESC LIMIT 2;",
                        name="nocase", outputs=True)
    assert [group["count"] for group in record["trace"][0]["groups"]] == [1, 1]
    assert len(record["trace"][0]["groups"][1]["rows"]) == 2
    inherited = record_sql("CREATE TABLE t(x TEXT COLLATE NOCASE); INSERT INTO t VALUES('a'),('A'),('b');",
                           "SELECT x AS key FROM t ORDER BY key;", name="inherited", outputs=True)
    assert [group["count"] for group in inherited["trace"][0]["groups"]] == [2, 1]
    record = record_sql(setup, "SELECT k, count(*) AS n FROM t GROUP BY k ORDER BY n DESC, k;",
                        name="grouped", outputs=True)
    assert sum(group["count"] for group in record["trace"][0]["groups"]) == 3
    with pytest.raises(ValueError, match="tie structure not observable"):
        record_sql(setup, "SELECT v FROM t ORDER BY k;", name="hidden", outputs=True)
    with pytest.raises(ValueError, match="unspecified choice inside a write"):
        record_sql(setup, "INSERT INTO t SELECT k,v FROM t LIMIT 1 RETURNING k;", name="write-cut", outputs=True)


def test_query_window_parameters_and_deterministic_write() -> None:
    """Slot identities, comments and CTE windows survive probing; unique-key writes run once."""
    from conformance.native_record import record_sql
    from conformance.corpus import native_replay
    setup = "CREATE TABLE t(k INTEGER,v); INSERT INTO t VALUES(1,'a'),(2,'b'),(3,'c');"
    for sql, parameters in [
        ("SELECT k,v FROM t WHERE k>:min ORDER BY 1 DESC NULLS LAST LIMIT :n; -- LIMIT ?", ((1, 0), (1, 2))),
        ("WITH chosen AS (SELECT * FROM t LIMIT 3) SELECT k,v FROM chosen ORDER BY k LIMIT ?,?;", ((1, 1), (1, 1))),
        ("SELECT k,v FROM t LIMIT ? OFFSET ?;", ((1, 1), (1, 1))),
        ("SELECT k AS x FROM t UNION SELECT 4 ORDER BY x;", ()),
        ("SELECT a.* FROM t AS a ORDER BY a.k DESC;", ()),
        ("SELECT a.k AS renamed FROM t AS a ORDER BY a.k;", ()),
    ]:
        record = record_sql(setup, sql, name="windows", outputs=True, parameters=[parameters])
        assert record["trace"][0]["groups"] is not None
        native_replay([record])
    record = record_sql(setup, "INSERT INTO t SELECT k+10,v FROM t ORDER BY 1 LIMIT 1 RETURNING k;",
                        name="specified-write", outputs=True)
    assert record["trace"][0]["changes"] == 1
    assert len(record["trace"][0]["visible"]["tables"][0]["rows"]) == 4


def test_sqlite_identifier_spelling() -> None:
    """Quoted punctuation survives and Unicode names are not folded as ASCII aliases."""
    from conformance.native_record import record_sql
    record = record_sql('CREATE TABLE t("k]" INTEGER); INSERT INTO t VALUES(2),(1);',
                        'SELECT "k]" FROM t ORDER BY "k]";', name="quoted-key", outputs=True)
    assert len(record["trace"][0]["groups"]) == 2
    with pytest.raises(ValueError, match="tie structure not observable"):
        record_sql('CREATE TABLE t("ß" INTEGER); INSERT INTO t VALUES(2),(1);',
                   'SELECT "ß" FROM t ORDER BY "ss";', name="unicode-key", outputs=True)
