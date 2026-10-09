"""Live pinned SQLite, compiled classification, serialization and kernel proof parity."""

from copy import deepcopy
import json
from pathlib import Path
import subprocess

import pytest

from conformance.native_trace import Fixture, record
from conformance.model_check import compiled, evaluate, prove
from conformance.pipeline import fixtures
from conformance.record_parser import default_parser

pytestmark = [pytest.mark.integration, pytest.mark.conformance, pytest.mark.kernel,
              pytest.mark.requires_lean, pytest.mark.requires_native("parser-library", "sqlite3")]


@pytest.mark.parametrize("ending", ["COMMIT;", "ROLLBACK;", "", "BEGIN; COMMIT;",
    "INSERT INTO records(id,payload) VALUES(9,X'00'); COMMIT;"])
def test_transaction_observation(ending: str, runtime_root: Path) -> None:
    """Open transactions retain earlier writes after errors and expose the committed snapshot."""
    fixture = Fixture("CREATE TABLE records(id INTEGER NOT NULL,payload BLOB,UNIQUE(id));",
        "BEGIN; INSERT INTO records(id,payload) VALUES(9,X''); "
        "UPDATE records SET payload=X'ff00' WHERE id=9; " + ending, {}, "transaction")
    case = record(fixture, default_parser(runtime_root))
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
    case = record(fixtures()[0], default_parser(runtime_root))
    wrong = deepcopy(case)
    wrong["nativeTrace"][-1]["visible"] = []
    rejected = compiled(wrong, runtime_root, emit_lean=True)
    assert rejected["verdict"] == "DISAGREE"
    prove(rejected["caseLean"], runtime_root, tmp_path / "WrongTrace.lean", case=wrong, expected=False)
    with pytest.raises(AssertionError, match="false|failed"):
        prove(rejected["caseLean"], runtime_root, tmp_path / "FalseProof.lean", case=wrong)
    invalid = deepcopy(case)
    invalid["script"][0]["addColumn"]["column"]["notNull"] = True
    result = compiled(invalid, runtime_root, emit_lean=True)
    assert result["verdict"] == "MODEL_UNSUPPORTED"
    prove(result["caseLean"], runtime_root, tmp_path / "InvalidDefinition.lean", case=invalid, expected=False)
    fixture = Fixture("CREATE TABLE records(id INTEGER,UNIQUE(id));",
        "UPDATE records SET id=2 WHERE id=1;",
        {"records": [(1, ((3, b"not-a-number"),))]}, "unsupported-key-domain")
    domain = record(fixture, default_parser(runtime_root))
    result = compiled(domain, runtime_root, emit_lean=True)
    assert result["verdict"] == "MODEL_UNSUPPORTED"
    prove(result["caseLean"], runtime_root, tmp_path / "UnsupportedDomain.lean", case=domain, expected=False)


def test_exact_storage_and_wide_rows(runtime_root: Path) -> None:
    """Snapshots retain REAL bits, arbitrary TEXT/BLOB bytes, NULL, and nonempty wide rows."""
    fixture = Fixture("CREATE TABLE cells(i INTEGER,r REAL,t TEXT,b BLOB);",
        "ALTER TABLE cells ADD note TEXT;",
        {"cells": [(-4, ((1, -(2**63)), (2, 0x3FF8000000000000), (3, b"\xff\x00"), (4, b""))),
                   (9, ((5, None), (5, None), (3, b""), (4, b"\x00\xff")))]}, "storage")
    case = record(fixture, default_parser(runtime_root))
    assert compiled(case, runtime_root)["verdict"] == "AGREE"
    specials = Fixture("CREATE TABLE t(value REAL);", "", {"t": [
        (1, ((2, 0x7FF0000000000000),)), (2, ((2, 0xFFF0000000000000),))]}, "infinities")
    assert evaluate(specials, runtime_root)[1]["verdict"] == "AGREE"
    nan = Fixture(specials.schema_sql, "", {"t": [(1, ((2, 0x7FF8000000000001),))]}, "nan")
    case, verdict = evaluate(nan, runtime_root)
    assert verdict["verdict"] == "DISAGREE" and verdict["position"] is None
    assert case["nativeTrace"][0]["visible"][0][1]["rows"][0]["values"] == ["null"]
    wide = fixtures()[4]
    populated = Fixture(wide.schema_sql, wide.migration_sql,
                        {"full": [(7, tuple((3, b"x") for _ in range(2000)))]}, "wide")
    case = record(populated, default_parser(runtime_root))
    assert compiled(case, runtime_root)["verdict"] == "AGREE"
    assert len(case["nativeTrace"][0]["visible"][0][1]["rows"][0]["values"]) == 2000


def test_fail_closed_transport(runtime_root: Path) -> None:
    """Unsupported frontend SQL, malformed bytes and versions cannot become agreement."""
    case, answer = evaluate(Fixture("", "SELECT 1;", {}, "unsupported"), runtime_root)
    assert case is None and answer["verdict"] == "MODEL_UNSUPPORTED"
    case = record(fixtures()[0], default_parser(runtime_root))
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
    fixture = Fixture("CREATE TABLE Records(ID BIGINT PRIMARY KEY, Stamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP, "
        "Flag BOOLEAN, Value, UNIQUE(Flag)); CREATE UNIQUE INDEX By_ID ON Records(ID);",
        "ALTER TABLE records ADD extra NUMERIC;", {}, "schema-properties")
    case = record(fixture, default_parser(runtime_root))
    result = compiled(case, runtime_root, emit_lean=True)
    assert result["verdict"] == "AGREE", result
    assert result["decoded"] == case
    prove(result["caseLean"], runtime_root, tmp_path / "Metadata.lean", case=case)
    changed = deepcopy(case)
    changed["provenance"] = []
    with pytest.raises(AssertionError, match="did not evaluate to `true`"):
        prove(result["caseLean"], runtime_root, tmp_path / "ChangedTerm.lean", case=changed)


def test_native_metadata_catches_translator_faults(runtime_root: Path, tmp_path: Path,
                                                  monkeypatch: pytest.MonkeyPatch) -> None:
    """Independent PRAGMAs reject corrupted metadata even when the parser accepts it."""
    from dataclasses import replace
    from conformance import native_trace
    from conformance.native_connection import Connection, library_path, load_library
    from belay.sqlite.sql_tree import parse
    from belay.sqlite.translate import starting_schema
    sql = ("CREATE TABLE t(id BIGINT PRIMARY KEY, stamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP, "
           "flag INTEGER NOT NULL, value TEXT, UNIQUE(flag,value)); "
           "CREATE UNIQUE INDEX by_value ON t(value,flag);")
    parser = default_parser(runtime_root)
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
            native_trace.read_schema.cache_clear()
            monkeypatch.setattr(native_trace, "starting_schema", lambda tree: (faulty,))
            with pytest.raises(ValueError, match="Native .* differs"):
                native_trace.snapshot(connection, parser)
    finally:
        native_trace.read_schema.cache_clear()
        connection.close()


def test_schema_cache_and_batch(runtime_root: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    """Unchanged schemas reuse parsing; rollback restores metadata and batch order is exact."""
    from conformance import native_trace, model_check
    from belay.sqlite.sql_tree import SqlParser, Tree
    parser = native_trace.parse
    parsed: list[str] = []

    def counted(selected: SqlParser, source: bytes, name: str) -> Tree:
        """Count actual native schema parser invocations without replacing their behavior."""
        if name == "conformance-schema.sql":
            parsed.append(source.decode())
        return parser(selected, source, name)

    native_trace.read_schema.cache_clear()
    monkeypatch.setattr(native_trace, "parse", counted)
    fixture = Fixture("CREATE TABLE t(id INTEGER);",
        "BEGIN; ALTER TABLE t ADD a TEXT; ROLLBACK; "
        "BEGIN; ALTER TABLE t ADD b BLOB; COMMIT;", {}, "schema-cache")
    case = record(fixture, default_parser(runtime_root))
    assert len(parsed) == len(set(parsed)) == 3
    assert record(fixture, default_parser(runtime_root)) == case
    assert len(parsed) == 3
    assert case["nativeTrace"][3]["visible"] == case["nativeTrace"][0]["visible"]
    invalid = deepcopy(case)
    invalid["version"] = 2
    calls = []
    run = subprocess.run

    def counted_run(*args: object, **kwargs: object) -> subprocess.CompletedProcess[str]:
        """Delegate to the real runner while asserting one process for the whole batch."""
        calls.append(args)
        return run(*args, **kwargs)

    monkeypatch.setattr(model_check.subprocess, "run", counted_run)
    results = model_check.compiled_many([case, invalid, case], runtime_root)
    assert [r["verdict"] for r in results] == ["AGREE", "HARNESS_ERROR", "AGREE"]
    assert len(calls) == 1
