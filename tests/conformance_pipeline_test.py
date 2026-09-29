"""Live pinned SQLite, compiled classification, serialization and kernel proof parity."""

from copy import deepcopy
import json
from pathlib import Path
import subprocess

import pytest

from conformance.native_trace import Fixture, record
from conformance.model_check import compiled, evaluate, prove
from conformance.pipeline import fixtures

pytestmark = [pytest.mark.integration, pytest.mark.conformance, pytest.mark.kernel,
              pytest.mark.requires_lean, pytest.mark.requires_native("sqlite-parser", "sqlite3")]


@pytest.mark.parametrize("ending", ["COMMIT;", "ROLLBACK;", "", "BEGIN; COMMIT;",
    "INSERT INTO records(id,payload) VALUES(9,X'00'); COMMIT;"])
def test_transaction_observation(ending: str, runtime_root: Path) -> None:
    """Open transactions retain earlier writes after errors and expose the committed snapshot."""
    fixture = Fixture("CREATE TABLE records(id INTEGER NOT NULL,payload BLOB,UNIQUE(id));",
        "BEGIN; INSERT INTO records(id,payload) VALUES(9,X''); "
        "UPDATE records SET payload=X'ff00' WHERE id=9; " + ending, {}, "transaction")
    case = record(fixture, runtime_root / "build/sqlite-parser")
    answer = compiled(case, runtime_root)
    assert answer["verdict"] == "AGREE", answer
    pending = case["nativeTrace"][3]
    assert pending["transactionOpen"] is True
    assert pending["visible"] != pending["persisted"]
    if ending.startswith("INSERT"):
        assert case["nativeTrace"][-1]["primaryCode"] == 19
        assert case["nativeTrace"][-1]["extendedCode"] != 19
        assert case["nativeTrace"][-1]["transactionOpen"] is True
        assert len(case["nativeTrace"]) == 5  # COMMIT was not reached.


def test_wrong_trace_and_unsupported(runtime_root: Path, tmp_path: Path) -> None:
    """Wrong traces fail both tiers; data-domain and invalid-definition failures stay unsupported."""
    case = record(fixtures()[0], runtime_root / "build/sqlite-parser")
    wrong = deepcopy(case)
    wrong["nativeTrace"][-1]["visible"] = []
    rejected = compiled(wrong, runtime_root, emit_lean=True)
    assert rejected["verdict"] == "DISAGREE"
    prove(rejected["caseLean"], runtime_root, tmp_path / "WrongTrace.lean", expected=False)
    with pytest.raises(AssertionError, match="false|failed"):
        prove(rejected["caseLean"], runtime_root, tmp_path / "FalseProof.lean")
    invalid = deepcopy(case)
    invalid["script"][0]["addColumn"]["column"]["notNull"] = True
    result = compiled(invalid, runtime_root, emit_lean=True)
    assert result["verdict"] == "MODEL_UNSUPPORTED"
    prove(result["caseLean"], runtime_root, tmp_path / "InvalidDefinition.lean", expected=False)
    fixture = Fixture("CREATE TABLE records(id INTEGER,UNIQUE(id));",
        "UPDATE records SET id=2 WHERE id=1;",
        {"records": [(1, ((3, b"not-a-number"),))]}, "unsupported-key-domain")
    domain = record(fixture, runtime_root / "build/sqlite-parser")
    result = compiled(domain, runtime_root, emit_lean=True)
    assert result["verdict"] == "MODEL_UNSUPPORTED"
    prove(result["caseLean"], runtime_root, tmp_path / "UnsupportedDomain.lean", expected=False)


def test_exact_storage_and_wide_rows(runtime_root: Path) -> None:
    """Snapshots retain REAL bits, arbitrary TEXT/BLOB bytes, NULL, and nonempty wide rows."""
    fixture = Fixture("CREATE TABLE cells(i INTEGER,r REAL,t TEXT,b BLOB);",
        "ALTER TABLE cells ADD note TEXT;",
        {"cells": [(-4, ((1, -(2**63)), (2, 0x3FF8000000000000), (3, b"\xff\x00"), (4, b""))),
                   (9, ((5, None), (5, None), (3, b""), (4, b"\x00\xff")))]}, "storage")
    case = record(fixture, runtime_root / "build/sqlite-parser")
    assert compiled(case, runtime_root)["verdict"] == "AGREE"
    wide = fixtures()[4]
    populated = Fixture(wide.schema_sql, wide.migration_sql,
                        {"full": [(7, tuple((3, b"x") for _ in range(2000)))]}, "wide")
    case = record(populated, runtime_root / "build/sqlite-parser")
    assert compiled(case, runtime_root)["verdict"] == "AGREE"
    assert len(case["nativeTrace"][0]["visible"][0][1]["rows"][0]["values"]) == 2000


def test_fail_closed_transport(runtime_root: Path) -> None:
    """Unsupported frontend SQL, malformed bytes and versions cannot become agreement."""
    case, answer = evaluate(Fixture("", "SELECT 1;", {}, "unsupported"), runtime_root)
    assert case is None and answer["verdict"] == "MODEL_UNSUPPORTED"
    case = record(fixtures()[0], runtime_root / "build/sqlite-parser")
    wrong = deepcopy(case)
    wrong["version"] = 2
    assert compiled(wrong, runtime_root)["verdict"] == "HARNESS_ERROR"
    wrong = deepcopy(case)
    wrong["initial"][0][1]["rows"][0]["values"][1] = {"text": {"bytes": [256]}}
    assert compiled(wrong, runtime_root)["verdict"] == "HARNESS_ERROR"
    result = subprocess.run([str(runtime_root / ".lake/build/bin/conformance-runner")],
        input="not json\n" + json.dumps(case) + "\n", capture_output=True, text=True, timeout=10)
    assert [json.loads(line)["verdict"] for line in result.stdout.splitlines()] == ["HARNESS_ERROR", "AGREE"]


def test_preserved_schema_metadata(runtime_root: Path, tmp_path: Path) -> None:
    """Aliases, defaults, primary/unique keys and explicit indexes survive the shared codec."""
    fixture = Fixture("CREATE TABLE records(id BIGINT PRIMARY KEY, stamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP, "
        "flag BOOLEAN, value, UNIQUE(flag)); CREATE UNIQUE INDEX by_id ON records(id);",
        "ALTER TABLE records ADD extra NUMERIC;", {}, "schema-properties")
    case = record(fixture, runtime_root / "build/sqlite-parser")
    result = compiled(case, runtime_root, emit_lean=True)
    assert result["verdict"] == "AGREE", result
    assert result["decoded"] == case
    prove(result["caseLean"], runtime_root, tmp_path / "Metadata.lean")


def test_connection_dqs_profile(tmp_path: Path) -> None:
    """Each connection overrides default-library DQS and verifies both native settings."""
    from conformance.native_connection import Connection, NativeError, library_path, load_library
    library = load_library(library_path())
    assert not library.sqlite3_compileoption_used(b"DQS=0")
    for name in ("writer", "reader"):
        connection = Connection(library, tmp_path / name)
        try:
            assert connection.configure(1013, -1) == connection.configure(1014, -1) == 0
            with pytest.raises(NativeError):
                connection.query('SELECT "not_an_identifier";')
            with pytest.raises(NativeError):
                connection.query('CREATE TABLE t(x CHECK(x <> "not_an_identifier"));')
        finally:
            connection.close()


def test_native_metadata_catches_translator_faults(runtime_root: Path, tmp_path: Path,
                                                  monkeypatch: pytest.MonkeyPatch) -> None:
    """Independent PRAGMAs reject corrupted metadata even when the parser accepts it."""
    from dataclasses import replace
    from conformance import native_trace
    from conformance.native_connection import Connection, library_path, load_library
    from migration_check.sql_tree import parse
    from migration_check.translate import starting_schema
    sql = ("CREATE TABLE t(id BIGINT PRIMARY KEY, stamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP, "
           "flag INTEGER NOT NULL, value TEXT, UNIQUE(flag,value)); "
           "CREATE UNIQUE INDEX by_value ON t(value,flag);")
    parser = runtime_root / "build/sqlite-parser"
    table = starting_schema(parse(parser, sql.encode(), "metadata.sql"))[0]
    connection = Connection(load_library(library_path()), tmp_path / "metadata.db")
    try:
        connection.execute_script(sql)
        native_trace.snapshot(connection, parser)
        column = table.columns[2]
        faults = [replace(table, columns=table.columns[:2] + (replace(column, **change),) + table.columns[3:])
                  for change in ({"affinity": "text"}, {"name": "wrong"}, {"not_null": False},
                                 {"declared_type": "bigInt"}, {"current_timestamp": True})]
        faults += [replace(table, primary_key=()), replace(table, unique_keys=()),
                   replace(table, indexes=()), replace(table, indexes=(replace(table.indexes[0], unique=False),)),
                   replace(table, indexes=(replace(table.indexes[0], columns=("flag", "value")),))]
        for faulty in faults:
            monkeypatch.setattr(native_trace, "starting_schema", lambda tree: (faulty,))
            with pytest.raises(ValueError, match="Native .* differs"):
                native_trace.snapshot(connection, parser)
    finally:
        connection.close()
