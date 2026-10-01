"""Native records survive frontend limitations and replay through today's model."""

from pathlib import Path
import pytest

from conformance.native_record import record_sql
from conformance.native_replay import prepare
from conformance.model_check import compiled

pytestmark = [pytest.mark.integration, pytest.mark.conformance,
              pytest.mark.requires_lean, pytest.mark.requires_native("sqlite-parser", "sqlite3")]


def test_outside_subset_survives(runtime_root: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    """Constraints, WITHOUT ROWID, views and triggers are observable before model support."""
    def reject(*args: object, **kwargs: object) -> None:
        """Recording must not invoke frontend parsing even indirectly."""
        raise AssertionError("translator invoked by native recording")

    with monkeypatch.context() as patch:
        patch.setattr("migration_check.sql_tree.parse", reject)
        record = record_sql("CREATE TABLE t(k TEXT PRIMARY KEY,v INTEGER CHECK(v>0)) WITHOUT ROWID; "
            "CREATE VIEW v AS SELECT * FROM t; CREATE TRIGGER tr AFTER INSERT ON t "
            "BEGIN UPDATE t SET v=v+1 WHERE k=new.k; END;",
            "BEGIN; INSERT INTO t VALUES('a',1); ROLLBACK;", name="out-of-subset")
    assert len(record["initial"]["visible"]["schema"]) == 3
    assert record["trace"][1]["visible"]["tables"][0]["rows"][0]["values"][1] == {"integer": {"value": 2}}
    assert record["trace"][1]["persisted"] == record["initial"]["visible"]
    assert record["trace"][-1]["visible"] == record["initial"]["visible"]
    case, result = prepare(record, runtime_root / "build/sqlite-parser")
    assert case is None and result["verdict"] == "MODEL_UNSUPPORTED"
    assert record["migrationSql"] and record["trace"]


def test_native_record_replay(runtime_root: Path) -> None:
    """Frozen typed rows and traces become structural cases without rerunning native SQL."""
    record = record_sql("CREATE TABLE t(id INTEGER NOT NULL,UNIQUE(id)); INSERT INTO t VALUES(7);",
        "BEGIN; INSERT INTO t(id) VALUES(8); INSERT INTO t(id) VALUES(8); COMMIT;", name="replay")
    assert len(record["trace"]) == 3
    assert record["trace"][-1]["primaryCode"] == 19
    case, error = prepare(record, runtime_root / "build/sqlite-parser")
    assert case is not None, error
    assert compiled(case, runtime_root)["verdict"] == "AGREE"
    record["initial"]["visible"]["tables"][0]["columns"][0][3] = {"integer": {"value": 0}}
    assert prepare(record, runtime_root / "build/sqlite-parser")[1]["verdict"] == "HARNESS_ERROR"


def test_nonmain_state_cannot_disappear() -> None:
    """Excluded connection contexts fail acquisition rather than silently dropping objects."""
    with pytest.raises(ValueError, match="temporary schema"):
        record_sql("CREATE TEMP TABLE t(x);", "", name="temporary")


def test_statement_alignment_is_harness_error(runtime_root: Path) -> None:
    """A missing/merged observation cannot masquerade as a production model disagreement."""
    from copy import deepcopy
    record = record_sql("CREATE TABLE t(v BLOB);", "BEGIN; ROLLBACK;", name="alignment")
    for trace in (record["trace"][:1], record["trace"] + record["trace"][-1:]):
        broken = deepcopy(record)
        broken["trace"] = trace
        assert prepare(broken, runtime_root / "build/sqlite-parser")[1]["verdict"] == "HARNESS_ERROR"
    broken = deepcopy(record)
    broken["trace"] = [broken["trace"][-1]]
    broken["trace"][0]["primaryCode"] = 1
    assert prepare(broken, runtime_root / "build/sqlite-parser")[1]["verdict"] == "HARNESS_ERROR"
    record["trace"][0]["sql"] = "BEGIN; ROLLBACK;"
    assert prepare(record, runtime_root / "build/sqlite-parser")[1]["verdict"] == "HARNESS_ERROR"


def test_native_semantic_errors_are_recorded(tmp_path: Path) -> None:
    """Rowid mismatch and a real length-limit failure retain native result codes."""
    from conformance.native_connection import Connection, library_path, load_library
    from conformance.native_record import execute
    record = record_sql("CREATE TABLE t(v);", "INSERT INTO t(rowid,v) VALUES('no',1);", name="rowid")
    assert record["trace"][0]["primaryCode"] == 20
    connection = Connection(load_library(library_path()), tmp_path / "length.db")
    try:
        connection.library.sqlite3_limit(connection.handle, 0, 100)
        assert list(execute(connection, "SELECT zeroblob(101);"))[0]["primaryCode"] == 18
    finally:
        connection.close()


def test_trailing_queries_do_not_hide_migration_progress(runtime_root: Path) -> None:
    """Report only an agreeing migration prefix as query-blocked; keep queries and settings honest."""
    from conformance.corpus import replay
    records = [record_sql("CREATE TABLE t(v BLOB); INSERT INTO t VALUES(1);", sql, name=str(index))
               for index, sql in enumerate([
                   "ALTER TABLE t ADD x TEXT; SELECT * FROM t; PRAGMA table_info(t);",
                   "ALTER TABLE t RENAME TO renamed; SELECT * FROM renamed;",
                   "PRAGMA user_version=4;",
                   "SELECT * FROM t; ALTER TABLE t ADD x TEXT;", "EXPLAIN SELECT * FROM t;"])]
    report = replay(records, runtime_root)
    assert report["queryDiagnostics"] == {"BLOCKED_ONLY_BY_QUERIES": 1, "PREFIX_MODEL_UNSUPPORTED": 1, "OTHER_UNSUPPORTED": 3}
    assert records[0]["trace"][-2]["rows"] == [[{"integer": {"value": 1}}, "null"]]
    assert report["counts"] == {"MODEL_UNSUPPORTED": 5}


def test_external_files_are_rejected_before_creation(tmp_path: Path) -> None:
    """Excluded ATTACH cannot create files before the recorder notices its extra schema."""
    from conformance.native_connection import NativeError
    destination = tmp_path / "external.db"
    with pytest.raises(NativeError, match="authorized"):
        record_sql(f"ATTACH '{destination}' AS extra;", "", name="external")
    assert not destination.exists()
    with pytest.raises(ValueError, match="nondeterministic"):
        record_sql("CREATE TABLE t(v);", "INSERT INTO t VALUES(randomblob(8));", name="random")


def test_native_syntax_errors_remain_frontend_exclusions(runtime_root: Path) -> None:
    """Matching native/parser syntax rejection is unsupported input, not failed transport."""
    record = record_sql("CREATE TABLE t(v BLOB);", "SELECT FROM;", name="syntax-error")
    assert record["trace"][-1]["primaryCode"] == 1
    result = prepare(record, runtime_root / "build/sqlite-parser")[1]
    assert result["verdict"] == "MODEL_UNSUPPORTED" and result["frontendStatus"] == "INPUT_ERROR"
    record["trace"][-1]["primaryCode"] = 0
    assert prepare(record, runtime_root / "build/sqlite-parser")[1]["verdict"] == "HARNESS_ERROR"


def test_native_output_shape_bindings_and_probe_guard(tmp_path: Path) -> None:
    """Empty queries keep shape, binding preserves typed bytes, and probes cannot write."""
    from conformance.native_connection import Connection, library_path, load_library
    connection = Connection(load_library(library_path()), tmp_path / "outputs.db")
    try:
        empty = connection.query_result('SELECT 1 AS "value" WHERE 0;', readonly=True)
        assert empty.columns == ("value",) and empty.rows == []
        cells = ((1, -(2**63)), (2, 0x3FF0000000000000), (3, b"a\0b"), (4, b"\0\xff"), (5, None))
        result = connection.query_result("SELECT ?, ?, :text, :blob, :null;", cells, readonly=True)
        assert result.rows == [cells] and len(result.columns) == 5
        repeated = connection.query_result("SELECT :same, :same;", ((1, 42),))
        assert repeated.rows == [((1, 42), (1, 42))]
        for parameters in ((), ((1, 1), (1, 2))):
            with pytest.raises(ValueError, match="parameter slot"):
                connection.query_result("SELECT ?;", parameters)
        connection.query("CREATE TABLE t(x);")
        with pytest.raises(ValueError, match="read-only"):
            connection.query_result("INSERT INTO t VALUES(1) RETURNING x;", readonly=True)
        for forbidden in ("PRAGMA foreign_keys=ON;", "BEGIN;", "CREATE TABLE rejected(x);",
                          "EXPLAIN INSERT INTO t VALUES(9);", "EXPLAIN SELECT 1;", "SELECT random();"):
            with pytest.raises(ValueError, match="read-only"):
                connection.query_result(forbidden, readonly=True)
        recursive = connection.query_result("WITH RECURSIVE n(x) AS (VALUES(1) UNION ALL "
            "SELECT x+1 FROM n WHERE x<3) SELECT sum(x) FROM n;", readonly=True)
        assert recursive.rows == [((1, 6),)]
        assert not connection.transaction_open
        assert connection.query("PRAGMA foreign_keys;") == [((1, 0),)]
        assert connection.query("SELECT * FROM t;") == []
        returning = connection.query_result("INSERT INTO t VALUES(1) RETURNING x;")
        assert returning.columns == ("x",) and returning.rows == [((1, 1),)]
        import ctypes as c
        from conformance.native_connection import NativeError
        # The probe must delegate to and restore the acquisition authorizer.
        connection.authorizer = c.CFUNCTYPE(c.c_int, c.c_void_p, c.c_int,
            c.c_char_p, c.c_char_p, c.c_char_p, c.c_char_p)(
                lambda _ctx, action, _a, function, _db, _tr: int(action == 31 and function == b"abs"))
        connection.check(connection.library.sqlite3_set_authorizer(connection.handle, connection.authorizer, None))
        for readonly in (True, False):
            with pytest.raises(NativeError, match="authorized"):
                connection.query_result("SELECT abs(1);", readonly=readonly)
    finally:
        connection.close()


def test_record_outputs_and_direct_changes() -> None:
    """DML counts exclude triggers/cascades and never carry over into SELECT or DDL."""
    record = record_sql(
        "PRAGMA foreign_keys=ON; CREATE TABLE parent(id INTEGER PRIMARY KEY);"
        "CREATE TABLE child(id INTEGER REFERENCES parent ON DELETE CASCADE);"
        "CREATE TABLE audit(x); CREATE TRIGGER logged AFTER INSERT ON parent "
        "BEGIN INSERT INTO audit VALUES(new.id); INSERT INTO audit VALUES(new.id); END;"
        "INSERT INTO parent VALUES(1); INSERT INTO child VALUES(1);",
        "INSERT INTO parent VALUES(?) RETURNING id; SELECT id AS value FROM parent WHERE 0;"
        "WITH input(x) AS (VALUES(3)) INSERT INTO parent SELECT x FROM input;"
        "UPDATE parent SET id=id WHERE id=99; DELETE FROM parent WHERE id=1;"
        "CREATE TABLE copied AS SELECT * FROM parent; EXPLAIN INSERT INTO parent VALUES(4);",
        name="outputs", outputs=True, parameters=[((1, 2),), (), (), (), (), (), ()])
    assert record["nativeVersion"] == 3
    trace = record["trace"]
    assert [event["changes"] for event in trace] == [1, None, 1, 0, 1, None, None]
    assert trace[0]["columns"] == ["id"] and trace[0]["columnCount"] == 1
    assert trace[0]["rows"] == [[{"integer": {"value": 2}}]]
    assert trace[0]["parameters"] == [{"integer": {"value": 2}}]
    assert trace[1]["columns"] == ["value"] and trace[1]["rows"] == []
    tables = {table["name"]: table for table in trace[4]["visible"]["tables"]}
    assert tables["child"]["rows"] == []
    assert len(tables["audit"]["rows"]) == 6
    from conformance.corpus import native_replay
    native_replay([record])
    record["trace"][0]["changes"] = 2
    with pytest.raises(ValueError, match="Native replay changed"):
        native_replay([record])
    with pytest.raises(ValueError, match="parameter slot"):
        record_sql("", "SELECT ?;", name="missing-bind", outputs=True)
    with pytest.raises(ValueError, match="unexecuted statement"):
        record_sql("", "SELECT 1;", name="extra-bind", outputs=True, parameters=[(), ()])
    with pytest.raises(ValueError, match="require output recording"):
        record_sql("", "SELECT ?;", name="dropped-bind", parameters=[((1, 1),)])
