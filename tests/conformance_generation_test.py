"""Fixed-seed state machines, boundary exclusions, and a reproducibly shrunk disagreement."""

from copy import deepcopy
from pathlib import Path

from hypothesis import find, settings, strategies as st
import pytest

from conformance.case_format import Json
from conformance.generated_program import Program, command, native_laws
from conformance.model_check import acquire, compiled
from conformance.native_record import record_sql
from conformance.native_replay import prepare
from conformance.regressions import freeze, minimize
from conformance.state_machine import generate
from conformance.record_parser import default_parser, runtime_library

pytestmark = [pytest.mark.integration, pytest.mark.conformance,
              pytest.mark.requires_lean, pytest.mark.requires_native("parser-library", "sqlite3")]


@pytest.mark.parametrize("error_seeking", [False, True])
def test_stateful_modes(runtime_root: Path, error_seeking: bool) -> None:
    """Both modes reach compiled comparison, with native law checks on every executed case."""
    counts, cases, boundaries = generate(runtime_root, error_seeking=error_seeking)
    assert counts["AGREE"] == len(cases) and len(cases) >= 20
    assert counts["MODEL_UNSUPPORTED"] == len(boundaries) and boundaries
    if error_seeking:
        from conformance.mutation_check import measure
        mutations = measure(cases, runtime_root)
        assert all(item["killed"] for item in mutations["mutants"].values()), mutations
    assert len({case["schemaSql"] for case in cases}) >= 4
    assert any(event["visible"] != case["nativeTrace"][index]["visible"]
               for case in cases for index, event in enumerate(case["nativeTrace"][1:])
               if isinstance(case["script"][index], dict) and "update" in case["script"][index])
    assert any(dict(case["initial"])["exists_table"]["rows"] for case in cases if "exists_table" in dict(case["initial"]))


@pytest.mark.parametrize("literal", ["'1'", "' 1'", "'1.0'", "1e20", "0.0", "-0.0", "9223372036854775808"])
def test_affinity_boundaries_remain_unsupported(runtime_root: Path, literal: str) -> None:
    """Native affinity observations are retained even when no structural case can be admitted."""
    native = record_sql("CREATE TABLE t(id INTEGER,UNIQUE(id));",
                        f"INSERT INTO t(id) VALUES({literal});", name=f"boundary-{literal}")
    case, answer = prepare(native, runtime_library(runtime_root))
    if case is not None:
        answer = compiled(case, runtime_root)
    assert answer["verdict"] == "MODEL_UNSUPPORTED"
    assert native["trace"]


def test_column_boundary(runtime_root: Path) -> None:
    """The error-seeking boundary reaches the real 2000-column failure and atomicity check."""
    program = Program([command("addColumn", "wide", column="extra")],
        Program().schema + "CREATE TABLE wide(" + ",".join(f"c{i} BLOB" for i in range(2000)) + ");")
    program.roundtrip(default_parser(runtime_root))
    case, error = acquire(program.fixture(), runtime_root)
    assert case is not None, error
    assert case["nativeTrace"][-1]["primaryCode"] == 1
    native_laws(case)
    assert compiled(case, runtime_root)["verdict"] == "AGREE"


def test_shrink_delete_and_freeze(runtime_root: Path, tmp_path: Path) -> None:
    """An injected structural transport bug shrinks and becomes a proof after restoration."""
    def oracle(program: Program) -> dict[str, Json]:
        """Change only model input, never the recorded native trace, to simulate a harness bug."""
        case, error = acquire(program.fixture(), runtime_root)
        if case is None:
            return error
        broken = deepcopy(case)
        for statement in broken["script"]:
            if isinstance(statement, dict) and "insert" in statement:
                statement["insert"]["values"][1] = {"integer": {"value": 99}}
                break
        return compiled(broken, runtime_root)

    values = find(st.lists(st.integers(min_value=0, max_value=5), min_size=1, max_size=6),
        lambda values: oracle(Program([command("insert", "t", key=i+2, value=value)
                                      for i, value in enumerate(values)]))["verdict"] == "DISAGREE",
        settings=settings(max_examples=30, derandomize=True, database=None, deadline=None))
    assert values == [0]
    program = Program([command("insert", "t", key=2, value=values[0]), command("update", "t", key=1, value=None)])
    minimal = minimize(program, oracle)
    assert len(minimal.commands) == 1 and oracle(minimal) == oracle(program)
    entry = freeze(minimal, runtime_root, tmp_path / "regression", classification="harness bug",
        resolution="Injected literal corruption removed; original native trace reacquired unchanged.", injected=True)
    assert entry["status"] == "resolved"


def test_frozen_regression(runtime_root: Path, tmp_path: Path) -> None:
    """Retained tier-two evidence is reacquired and kernel-checked on every model test run."""
    import hashlib
    import json
    import os
    import subprocess
    from conformance.model_assertions import audit_axioms
    directory = Path(__file__).resolve().parents[1] / "conformance/regressions/injected-literal-corruption"
    case_file = directory / "case.json"
    entry = json.loads((directory / "mismatch.json").read_text())
    assert hashlib.sha256(case_file.read_bytes()).hexdigest() == entry["caseSha256"]
    program = Program([command("insert", "t", key=2, value=0)])
    fresh, error = acquire(program.fixture(), runtime_root)
    assert fresh == json.loads(case_file.read_text()), error
    from conformance.model_check import prove
    result = compiled(fresh, runtime_root, emit_lean=True)
    assert result['verdict'] == 'AGREE'
    term = result['caseLean']
    assert isinstance(term, str)
    audit_axioms(prove(term, runtime_root, tmp_path / 'CurrentRegression.lean', case=fresh))
