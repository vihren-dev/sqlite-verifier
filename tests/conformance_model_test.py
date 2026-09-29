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
from migration_check.sql_model import Affinity, Column, Table, transition
from migration_check.sql_tree import parse
from migration_check.translate import statements

pytestmark = [pytest.mark.integration, pytest.mark.conformance, pytest.mark.kernel,
              pytest.mark.requires_lean, pytest.mark.requires_native("sqlite-parser", "sqlite3")]


@pytest.mark.parametrize("name", [case.name for case in cases()])
def test_native_model(name: str, runtime_root: Path, tmp_path: Path) -> None:
    """The unchanged five fixtures agree natively, round-trip, and receive kernel proofs."""
    index = next(i for i, case in enumerate(cases()) if case.name == name)
    old, fixture = cases()[index], fixtures()[index]
    case = record(fixture, runtime_root / "build/sqlite-parser")
    frozen = json.loads((Path(__file__).resolve().parents[1] / "conformance/cases" / f"{name}.json").read_text())
    assert case == frozen, "Native replay differs from the frozen pinned-engine record"
    before = tuple(Table(table.name, tuple(Column(name, cast(Affinity, kind.lower()))
                   for name, kind in table.columns)) for table in old.before)
    after = tuple(Table(table.name, tuple(Column(name, cast(Affinity, kind.lower()))
                  for name, kind in table.columns)) for table in old.after)
    script = statements(parse(runtime_root / "build/sqlite-parser", fixture.migration_sql.encode(), "case.sql"))
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
    prove(answer["caseLean"], runtime_root, tmp_path / "Regression.lean", failure=old.lean_failure)


def test_lost_rows_rejected(runtime_root: Path, tmp_path: Path) -> None:
    """A falsely empty target fails the shared checker and cannot receive a kernel proof."""
    case = record(fixtures()[0], runtime_root / "build/sqlite-parser")
    case["nativeTrace"][-1]["visible"][1][1]["rows"] = []
    result = compiled(case, runtime_root, emit_lean=True)
    assert result["verdict"] == "DISAGREE"
    prove(result["caseLean"], runtime_root, tmp_path / "Rejected.lean", expected=False)
    with pytest.raises(AssertionError, match="false|failed"):
        prove(result["caseLean"], runtime_root, tmp_path / "FalseProof.lean")
