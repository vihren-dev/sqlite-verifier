"""Live pinned SQLite, compiled classification, serialization and kernel proof parity."""

from pathlib import Path
from typing import cast
import json

import pytest

from conformance.case_format import Json, literal_cell, row_wire
from conformance.model_cases import ExpectedTable, cases
from conformance.native_trace import record
from conformance.model_check import compiled, prove
from conformance.pipeline import fixtures
from conformance.record_parser import default_parser, runtime_library

pytestmark = [pytest.mark.integration, pytest.mark.conformance, pytest.mark.kernel,
              pytest.mark.requires_lean, pytest.mark.requires_native("parser-library", "sqlite3")]


def native_expected(table: ExpectedTable) -> Json:
    """The native table that an authored expectation describes: plain typed columns and its rows."""
    return {"name": table.name, "columns": [{"name": name, "declaredType": kind, "notNull": False, "defaultValue": None}
                                           for name, kind in table.columns],
            "primaryKey": [[column for column, _ in table.columns].index(key) for key in table.primary_key],
            "uniqueKeys": [],
            "indexes": [{"name": name, "columns": [[column for column, _ in table.columns].index(key) for key in keys],
                         "unique": unique} for name, keys, unique in table.indexes],
            "rows": [row_wire(int(row[0]), tuple(literal_cell(value) for value in row[1:])) for row in table.rows]}


@pytest.mark.parametrize("name", [case.name for case in cases()])
def test_native_model(name: str, runtime_root: Path, tmp_path: Path) -> None:
    """Each fixture agrees natively, matches its frozen record and round-trips; all but the
    2,000-column fixture (`kernel_proof`) also receive kernel proofs."""
    index = next(i for i, case in enumerate(cases()) if case.name == name)
    old, fixture = cases()[index], fixtures()[index]
    case = record(fixture, default_parser(runtime_root))
    frozen = json.loads((Path(__file__).resolve().parents[1] / "conformance/cases" / f"{name}.json").read_text())
    assert frozen["version"] == 4
    # Retained fixtures have no defaults; their syntax and native observations are unchanged.
    from conformance.case_format import CASE_VERSION
    assert case == {**frozen, "version": CASE_VERSION}, "Native replay differs from the frozen pinned-engine record"
    expected = [native_expected(table) for table in sorted(old.after, key=lambda table: table.name)]
    assert case["nativeTrace"][-1]["visible"] == expected
    assert old.native_error in dict(cast(list[list[str]], case["provenance"]))["nativeError"]
    answer = compiled(case, runtime_root, emit_lean=True)
    assert answer["verdict"] == "AGREE", answer
    assert answer["decoded"] == case
    if old.kernel_proof:
        prove(answer["caseLean"], runtime_root, tmp_path / "Regression.lean", case=case, failure=old.lean_failure)


def test_lost_rows_rejected(runtime_root: Path, tmp_path: Path) -> None:
    """A falsely empty target fails the shared checker and cannot receive a kernel proof."""
    case = record(fixtures()[0], default_parser(runtime_root))
    case["nativeTrace"][-1]["visible"][1]["rows"] = []
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
    assert case["version"] == 5 and case["outputs"] is not None
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
    # The LIMIT cuts the tie group of k = 1; the model's row is a submultiset of it (ADR 0005).
    model, answer = prepare(ordered, runtime_library(runtime_root))
    assert model is not None and compiled(model, runtime_root)["verdict"] == "AGREE", answer
    ordered["trace"][0]["groups"][0]["count"] = 3
    assert prepare(ordered, runtime_library(runtime_root))[1]["verdict"] == "HARNESS_ERROR"
    native["trace"][0]["columnCount"] = 1
    assert prepare(native, runtime_library(runtime_root))[1]["verdict"] == "HARNESS_ERROR"


def test_lowered_limit_is_read_from_the_case(runtime_root: Path) -> None:
    """`VerifierConformance.Case.classifyCase` resolves under the recorded profile: under the
    documented 2,000-column limit, the native too-many-columns error of a lowered limit disagrees."""
    index = next(i for i, case in enumerate(cases()) if case.name == "lowered_limit_exceeded")
    case = record(fixtures()[index], default_parser(runtime_root))
    assert case["profile"]["limits"]["columns"] == 5
    assert compiled(case, runtime_root)["verdict"] == "AGREE"
    case["profile"]["limits"]["columns"] = 2000
    assert compiled(case, runtime_root)["verdict"] == "DISAGREE"
