"""Fault injection checks the differential pipeline against model and native failures."""

import os
from pathlib import Path
import subprocess
from textwrap import indent

import pytest

from conformance.native_connection import Connection
from conformance.native_trace import Fixture, initialize, record
from conformance.model_check import compiled, evaluate
from belay.sqlite.sql_model import Table

ROOT = Path(__file__).resolve().parents[1]
pytestmark = [pytest.mark.integration, pytest.mark.conformance, pytest.mark.kernel,
              pytest.mark.requires_lean, pytest.mark.requires_native("sqlite-parser", "sqlite3")]


def test_model_mutation(runtime_root: Path, tmp_path: Path) -> None:
    """Dropping INSERT in an isolated copy of the production model yields DISAGREE in both tiers."""
    fixture = Fixture("CREATE TABLE records(id INTEGER);",
        "BEGIN; INSERT INTO records(id) VALUES(9); COMMIT;", {}, "insert-mutant")
    case = record(fixture, runtime_root / "build/sqlite-parser")
    result = compiled(case, runtime_root, emit_lean=True)
    assert result["verdict"] == "AGREE"
    sources = []
    for filename in ("SqliteVerifier/SqlExecution.lean", "VerifierConformance/Trace.lean",
                     "VerifierConformance/Outputs.lean", "VerifierConformance/Case.lean"):
        source = (ROOT / filename).read_text()
        source = "\n".join(line for line in source.splitlines() if not line.startswith("import "))
        source = source.replace("namespace SqliteVerifier", "namespace SqliteVerifier.Mutant")
        source = source.replace("end SqliteVerifier", "end SqliteVerifier.Mutant")
        if filename == "SqliteVerifier/SqlExecution.lean":
            assert source.count("LiteralData.inserted table values") == 1
            source = source.replace("LiteralData.inserted table values", "table")
        sources.append(source)
    proof = tmp_path / "Mutant.lean"
    proof.write_text("import VerifierConformance.Case\n" + "\n".join(sources) +
        "\nopen SqliteVerifier.Mutant.Conformance\n"
        "def mutantCase : Case :=\n" + indent(result["caseLean"], "  ") + "\n"
        "theorem detected : classifyCase mutantCase = .disagree (some 1) := by decide +kernel\n"
        '#eval if decide (classifyCase mutantCase = .disagree (some 1)) then "MUTANT_DISAGREES" else "MUTANT_SURVIVED"\n'
        "#print axioms detected\n")
    checked = subprocess.run([str(runtime_root / "lean/bin/lean"), str(proof)],
        env={**os.environ, "LEAN_PATH": str(runtime_root / ".lake/build/lib/lean")},
        capture_output=True, text=True, timeout=30)
    assert checked.returncode == 0, checked.stdout + checked.stderr
    assert '"MUTANT_DISAGREES"' in checked.stdout, checked.stdout
    assert not any(token in checked.stdout for token in ("sorryAx", "ofReduceBool", "_native"))


def test_locked_native_snapshot_is_harness_error(runtime_root: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    """A real second-connection SQLITE_BUSY prevents any case from reaching comparison."""
    def initialize_locked(connection: Connection, schema: tuple[Table, ...], fixture: Fixture) -> None:
        """Inject a native exclusive lock after the otherwise ordinary fixture initialization."""
        initialize(connection, schema, fixture)
        connection.execute_script("BEGIN EXCLUSIVE;")

    monkeypatch.setattr("conformance.native_trace.initialize", initialize_locked)
    case, verdict = evaluate(Fixture("CREATE TABLE records(id INTEGER);",
                            "ALTER TABLE records ADD note TEXT;", {}, "locked"), runtime_root)
    assert case is None
    assert verdict["verdict"] == "HARNESS_ERROR"
    assert "locked" in verdict["error"], verdict
