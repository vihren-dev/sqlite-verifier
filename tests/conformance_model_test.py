"""Verify native/model agreement through production translation, plus a failing model assertion."""

from dataclasses import replace
import os
from pathlib import Path
import subprocess
import sys

import pytest
from tempfile import TemporaryDirectory

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(ROOT / "conformance"))

from migration_check.sql_model import schema_inputs, sql_inputs
from migration_check.sql_tree import parse
from migration_check.translate import starting_schema, statements
from model_assertions import assertions
from model_cases import cases, schema_sql
from model_check import run


pytestmark = [pytest.mark.integration, pytest.mark.conformance, pytest.mark.kernel,
              pytest.mark.parser, pytest.mark.requires_lean]


@pytest.mark.requires_native("sqlite-parser", "sqlite3")
@pytest.mark.parametrize("name", [case.name for case in cases()])
def test_native_model(name: str, runtime_root: Path,
                      lean_sysroot: Path, lean_library: Path) -> None:
    """A native case matches independent rows/errors and its production translation kernel-checks."""
    case = next(case for case in cases() if case.name == name)
    reports = run(os.environ.get("SQLITE3", "sqlite3"), runtime_root / "build/sqlite-parser", (case,), runtime_root,
                  compiler=lean_sysroot / "bin/lean", library=lean_library)
    assert [report["case"] for report in reports] == [name]


@pytest.mark.requires_native("sqlite-parser")
def test_lost_rows_rejected(runtime_root: Path, lean_sysroot: Path, lean_library: Path) -> None:
    """A falsely empty target cannot receive an accepted concrete model proof."""
    parser = runtime_root / "build/sqlite-parser"
    case = cases()[0]
    before = starting_schema(parse(parser, schema_sql(case.before).encode(), "schema.sql"))
    migration = statements(parse(parser, case.migration.encode(), "migration.sql"))
    falsely_empty = replace(case, after=(replace(case.after[0], rows=()), case.after[1]))
    with TemporaryDirectory() as directory:
        proof = Path(directory) / "LostRows.lean"
        generated = schema_inputs(before) + sql_inputs(before, migration).removeprefix("import SchemaInputs\n")
        proof.write_text(generated + assertions(falsely_empty))
        rejected = subprocess.run([str(lean_sysroot / "bin/lean"), str(proof)], cwd=runtime_root,
                                  env={**os.environ, "LEAN_PATH": str(lean_library)},
                                  text=True, capture_output=True, timeout=30)
    assert rejected.returncode != 0, "False empty-target expectation received an accepted proof"
    assert "false" in rejected.stdout.lower(), rejected.stdout + rejected.stderr
