"""Universal production-transition laws and native witnesses for their preconditions."""

import os
from pathlib import Path
import subprocess

import pytest

from conformance.model_assertions import audit_axioms
from conformance.native_trace import Fixture, record

pytestmark = [pytest.mark.integration, pytest.mark.conformance, pytest.mark.kernel,
              pytest.mark.requires_lean, pytest.mark.requires_native("sqlite-parser", "sqlite3")]


def test_laws_kernel(runtime_root: Path) -> None:
    """Compile the actual universal proofs and reject all forbidden proof-oracle axioms."""
    source = Path(__file__).resolve().parents[1] / "packages/belay-sqlite/Belay/Sqlite/Laws.lean"
    checked = subprocess.run([str(runtime_root / "lean/bin/lean"), str(source)],
        env={**os.environ, "LEAN_PATH": os.pathsep.join(str(runtime_root / path) for path in (".lake/build/lib/lean", "packages/belay-sqlite/.lake/build/lib/lean"))},
        capture_output=True, text=True, timeout=30)
    assert checked.returncode == 0, checked.stdout + checked.stderr
    audit_axioms(checked.stdout)
    for name in ("rollback", "statement_atomicity", "add_column_shape"):
        assert f"Belay.Sqlite.Conformance.{name}' depends on axioms" in checked.stdout


@pytest.mark.parametrize("size", [0, 1, 5])
def test_native_laws(size: int, runtime_root: Path) -> None:
    """Rollback, failing statement atomicity and populated ADD obey the universal law shapes."""
    fixture = Fixture("CREATE TABLE t(id INTEGER NOT NULL,UNIQUE(id));",
        "BEGIN; INSERT INTO t(id) VALUES(99); ALTER TABLE t ADD note TEXT; ROLLBACK;",
        {"t": [(n - 4, ((1, n),)) for n in range(size)]}, "native-laws")
    trace = record(fixture, runtime_root / "build/sqlite-parser")["nativeTrace"]
    assert trace[-1]["visible"] == trace[0]["visible"]
    before = trace[2]["visible"][0][1]["rows"]
    after = trace[3]["visible"][0][1]["rows"]
    assert after == [{"rowid": row["rowid"], "values": row["values"] + ["null"]} for row in before]
    failed = Fixture(fixture.schema_sql,
        "BEGIN; INSERT INTO t(id) VALUES(99); INSERT INTO t(id) VALUES(99);", fixture.rows, "atomicity")
    trace = record(failed, runtime_root / "build/sqlite-parser")["nativeTrace"]
    assert trace[-1]["primaryCode"] == 19
    assert trace[-1]["visible"] == trace[-2]["visible"]
    assert trace[-1]["persisted"] == trace[0]["visible"]
