"""Live pinned SQLite, compiled classification, serialization and kernel proof parity."""

from pathlib import Path
from typing import cast
import json

import pytest

from conformance.case_format import literal_cell, schema_wire, table_wire
from conformance.model_cases import cases
from conformance.native_trace import record
from conformance.model_check import compiled, prove
from conformance.pipeline import fixtures
from belay.sqlite.sql_model import Affinity, Column, Table, transition
from belay.sqlite.sql_tree import parse
from belay.sqlite.translate import statements
from conformance.record_parser import default_parser, runtime_library

pytestmark = [pytest.mark.integration, pytest.mark.conformance, pytest.mark.kernel,
              pytest.mark.requires_lean, pytest.mark.requires_native("parser-library", "sqlite3")]


@pytest.mark.parametrize("name", [case.name for case in cases()])
def test_native_model(name: str, runtime_root: Path, tmp_path: Path) -> None:
    """The unchanged five fixtures agree natively, round-trip, and receive kernel proofs."""
    index = next(i for i, case in enumerate(cases()) if case.name == name)
    old, fixture = cases()[index], fixtures()[index]
    case = record(fixture, default_parser(runtime_root))
    frozen = json.loads((Path(__file__).resolve().parents[1] / "conformance/cases" / f"{name}.json").read_text())
    assert case == frozen, "Native replay differs from the frozen pinned-engine record"
    before = tuple(Table(table.name, tuple(Column(name, cast(Affinity, kind.lower()))
                   for name, kind in table.columns)) for table in old.before)
    after = tuple(Table(table.name, tuple(Column(name, cast(Affinity, kind.lower()))
                  for name, kind in table.columns)) for table in old.after)
    script = statements(parse(default_parser(runtime_root), fixture.migration_sql.encode(), "case.sql"))
    assert case["schema"] == [schema_wire(table) for table in before]
    assert transition(before, script)[0] == after
    expected = [[table.name, table_wire(
        Table(table.name, tuple(Column(name, cast(Affinity, kind.lower())) for name, kind in table.columns)),
        [(int(row[0]), tuple(literal_cell(value) for value in row[1:])) for row in table.rows])]
        for table in sorted(old.after, key=lambda table: table.name)]
    assert case["nativeTrace"][-1]["visible"] == expected
    assert old.native_error in dict(case["provenance"])["nativeError"]
    answer = compiled(case, runtime_root, emit_lean=True)
    assert answer["verdict"] == "AGREE", answer
    assert answer["decoded"] == case
    prove(answer["caseLean"], runtime_root, tmp_path / "Regression.lean", case=case, failure=old.lean_failure)


def test_lost_rows_rejected(runtime_root: Path, tmp_path: Path) -> None:
    """A falsely empty target fails the shared checker and cannot receive a kernel proof."""
    case = record(fixtures()[0], default_parser(runtime_root))
    case["nativeTrace"][-1]["visible"][1][1]["rows"] = []
    result = compiled(case, runtime_root, emit_lean=True)
    assert result["verdict"] == "DISAGREE"
    prove(result["caseLean"], runtime_root, tmp_path / "Rejected.lean", case=case, expected=False)
    with pytest.raises(AssertionError, match="false|failed"):
        prove(result["caseLean"], runtime_root, tmp_path / "FalseProof.lean", case=case)


def test_version_two_outputs(runtime_root: Path, tmp_path: Path) -> None:
    """The compiled and kernel classifiers check direct counts as well as stored state."""
    from copy import deepcopy
    from conformance.native_record import record_sql
    from conformance.native_replay import prepare
    native = record_sql("CREATE TABLE t(id INTEGER NOT NULL,v BLOB,UNIQUE(id)); INSERT INTO t VALUES(1,7);",
        "BEGIN; UPDATE t SET v=7 WHERE id=1; UPDATE t SET v=8 WHERE id=2;"
        "INSERT INTO t(id,v) VALUES(2,8); INSERT INTO t(id,v) VALUES(2,9); COMMIT;",
        name="outputs-v2", outputs=True)
    case, error = prepare(native, runtime_library(runtime_root))
    assert case is not None, error
    assert case["version"] == 2
    answer = compiled(case, runtime_root, emit_lean=True)
    assert answer["verdict"] == "AGREE", answer
    assert answer["decoded"] == case
    prove(answer["caseLean"], runtime_root, tmp_path / "OutputsAgree.lean", case=case)
    wrong = deepcopy(case)
    wrong["outputs"][1]["result"]["changes"] = 0  # Matched unchanged row still counts.
    answer = compiled(wrong, runtime_root, emit_lean=True)
    assert answer["verdict"] == "DISAGREE" and answer["position"] == 1
    prove(answer["caseLean"], runtime_root, tmp_path / "OutputsReject.lean", case=wrong, expected=False)
    wrong = deepcopy(case)
    wrong["outputs"][0]["result"]["columns"] = ["unexpected"]
    assert compiled(wrong, runtime_root)["verdict"] == "DISAGREE"
    wrong["outputs"].pop()
    assert compiled(wrong, runtime_root)["verdict"] == "HARNESS_ERROR"
    for sql, parameters in (("SELECT 1;", None), ("INSERT INTO t(id,v) VALUES(?,?);", [((1, 3), (1, 4))])):
        unsupported = record_sql("CREATE TABLE t(id INTEGER,v BLOB);", sql,
                                 name="unsupported-output", outputs=True, parameters=parameters)
        assert prepare(unsupported, runtime_library(runtime_root))[1]["verdict"] == "MODEL_UNSUPPORTED"
    ordered = record_sql("CREATE TABLE t(k); INSERT INTO t VALUES(1),(1),(2);",
                         "SELECT k FROM t ORDER BY k LIMIT 1;", name="ordered", outputs=True)
    assert prepare(ordered, runtime_library(runtime_root))[1]["verdict"] == "MODEL_UNSUPPORTED"
    ordered["trace"][0]["groups"][0]["count"] = 3
    assert prepare(ordered, runtime_library(runtime_root))[1]["verdict"] == "HARNESS_ERROR"
    native["trace"][0]["columnCount"] = 1
    assert prepare(native, runtime_library(runtime_root))[1]["verdict"] == "HARNESS_ERROR"
