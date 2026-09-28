"""Verify native/model agreement through production translation, plus a failing model assertion."""

from dataclasses import replace
import json
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
def test_native_model(name: str, runtime_root: Path, case_artifacts: Path,
                      lean_sysroot: Path, lean_library: Path) -> None:
    """A native case matches independent rows/errors and its production translation kernel-checks."""
    case = next(case for case in cases() if case.name == name)
    reports = run(os.environ.get("SQLITE3", "sqlite3"), runtime_root / "build/sqlite-parser", (case,), runtime_root,
                  compiler=lean_sysroot / "bin/lean", library=lean_library)
    assert [report["case"] for report in reports] == [name]
    assert reports[0]["model_status"] == "KERNEL_CHECKED_CONCRETE_ASSERTIONS"
    assert reports[0]["translation_status"] == "PRODUCTION_PIPELINE"
    case_artifacts.mkdir(parents=True, exist_ok=True)
    (case_artifacts / "native-model.json").write_text(json.dumps(reports, indent=2) + "\n")


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


def evidence() -> list[dict[str, object]]:
    """Retain the bounded report producer until the collector consumes pytest receipts."""
    reports = run(sys.argv[1] if len(sys.argv) == 2 else os.environ.get("SQLITE3", "sqlite3"), ROOT / "build/sqlite-parser")
    assert [report["case"] for report in reports] == [case.name for case in cases()]
    assert len(reports) == 5
    assert all(report["model_status"] == "KERNEL_CHECKED_CONCRETE_ASSERTIONS" for report in reports)
    assert all(report["translation_status"] == "PRODUCTION_PIPELINE" for report in reports)
    sysroot = Path(subprocess.run(["lean", "--print-prefix"], capture_output=True, text=True,
                                  check=True, timeout=10).stdout.strip())
    test_lost_rows_rejected(ROOT, sysroot, ROOT / ".lake/build/lib/lean")
    return reports


if __name__ == "__main__":
    print(json.dumps(evidence(), indent=2))
