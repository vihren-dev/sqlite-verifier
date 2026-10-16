"""Live pinned SQLite, compiled classification, serialization and kernel proof parity."""

from collections.abc import Callable
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
    """Wrong traces fail both tiers; restricted definitions stay unsupported; a key column that
    holds text, which SQLite stores and the model compares as SQLite does (slice 5a), agrees
    and has a kernel proof."""
    case = record(fixtures()[0], default_parser(runtime_root))
    wrong = deepcopy(case)
    wrong["nativeTrace"][-1]["visible"] = []
    rejected = compiled(wrong, runtime_root, emit_lean=True)
    assert rejected["verdict"] == "DISAGREE"
    prove(rejected["caseLean"], runtime_root, tmp_path / "WrongTrace.lean", case=wrong, expected=False)
    with pytest.raises(AssertionError, match="false|failed"):
        prove(rejected["caseLean"], runtime_root, tmp_path / "FalseProof.lean", case=wrong)
    invalid = deepcopy(case)
    invalid["script"][0]["addColumn"]["column"]["constraints"] = [{"notNull": {"algorithm": None}}]
    result = compiled(invalid, runtime_root, emit_lean=True)
    assert result["verdict"] == "MODEL_UNSUPPORTED"
    prove(result["caseLean"], runtime_root, tmp_path / "RestrictedDefinition.lean", case=invalid, expected=False)
    fixture = Fixture("CREATE TABLE records(id INTEGER,UNIQUE(id));",
        "UPDATE records SET id=2 WHERE id=1;",
        {"records": [(1, ((3, b"not-a-number"),))]}, "text-in-integer-key")
    domain = record(fixture, default_parser(runtime_root))
    result = compiled(domain, runtime_root, emit_lean=True)
    assert result["verdict"] == "AGREE", result
    prove(result["caseLean"], runtime_root, tmp_path / "TextKey.lean", case=domain)


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
    assert case["nativeTrace"][0]["visible"][0]["rows"][0]["values"] == ["null"]
    wide = fixtures()[4]
    populated = Fixture(wide.schema_sql, wide.migration_sql,
                        {"full": [(7, tuple((3, b"x") for _ in range(2000)))]}, "wide")
    case = record(populated, default_parser(runtime_root))
    assert compiled(case, runtime_root)["verdict"] == "AGREE"
    assert len(case["nativeTrace"][0]["visible"][0]["rows"][0]["values"]) == 2000


def test_fail_closed_transport(runtime_root: Path) -> None:
    """Unsupported frontend SQL, malformed bytes and versions cannot become agreement."""
    case, answer = evaluate(Fixture("", "SELECT 1;", {}, "unsupported"), runtime_root)
    assert case is None and answer["verdict"] == "MODEL_UNSUPPORTED"
    case = record(fixtures()[0], default_parser(runtime_root))
    wrong = deepcopy(case)
    wrong["version"] = 2
    assert compiled(wrong, runtime_root)["verdict"] == "HARNESS_ERROR"
    wrong = deepcopy(case)
    wrong["initial"][0]["rows"][0]["values"][1] = {"text": {"bytes": [256]}}
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


def test_catalog_comparison_catches_metadata_drift(runtime_root: Path) -> None:
    """Lean compares the resolved catalog with the native PRAGMA metadata; any drift disagrees.

    This checks `VerifierConformance.Native.tablesMatch`, which replaced the Python
    cross-check of the translated schema: each native metadata field is changed in a
    recorded case, and the compiled classifier must refuse the initial state.
    """
    sql = ("CREATE TABLE t(id BIGINT PRIMARY KEY, stamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP, "
           "flag INTEGER NOT NULL, value TEXT, UNIQUE(flag,value)); "
           "CREATE UNIQUE INDEX by_value ON t(value,flag);")
    case = record(Fixture(sql, "BEGIN; COMMIT;", {}, "metadata"), default_parser(runtime_root))
    assert compiled(case, runtime_root)["verdict"] == "AGREE"

    def changed(change: Callable[[dict[str, object]], object]) -> dict[str, object]:
        """A copy of the case whose initial table metadata is changed in every observation."""
        copy = deepcopy(case)
        for tables in [copy["initial"], *[observation[view] for observation in copy["nativeTrace"]
                                          for view in ("visible", "persisted")]]:
            change(tables[0])
        return copy

    faults = [
        lambda table: table["columns"][2].update(declaredType="TEXT"),
        lambda table: table["columns"][2].update(name="wrong"),
        lambda table: table["columns"][2].update(notNull=False),
        lambda table: table["columns"][1].update(defaultValue=None),
        lambda table: table.update(primaryKey=[]),
        lambda table: table.update(uniqueKeys=[]),
        lambda table: table.update(indexes=[]),
        lambda table: table["indexes"][0].update(unique=False),
        lambda table: table["indexes"][0].update(columns=[2, 3]),
        lambda table: table.update(name="T"),
    ]
    for fault in faults:
        answer = compiled(changed(fault), runtime_root)
        assert answer["verdict"] == "DISAGREE" and answer["position"] is None, answer


def test_rollback_restores_metadata_and_batch(runtime_root: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    """ROLLBACK restores the native catalog, recording is repeatable, and batch order is exact."""
    from conformance import model_check
    fixture = Fixture("CREATE TABLE t(id INTEGER);",
        "BEGIN; ALTER TABLE t ADD a TEXT; ROLLBACK; "
        "BEGIN; ALTER TABLE t ADD b BLOB; COMMIT;", {}, "schema-rollback")
    case = record(fixture, default_parser(runtime_root))
    assert record(fixture, default_parser(runtime_root)) == case
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
