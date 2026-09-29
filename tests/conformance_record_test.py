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
