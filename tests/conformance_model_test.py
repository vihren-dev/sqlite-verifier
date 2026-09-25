"""Verify native/model agreement through production translation, plus a failing model assertion."""

from dataclasses import replace
import json
import os
from pathlib import Path
import subprocess
import sys
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


def main() -> list[dict[str, object]]:
    """Check all five explicit cases, then demonstrate that lost rows cannot prove equal."""
    parser = ROOT / "build/sqlite-parser"
    reports = run(sys.argv[1] if len(sys.argv) == 2 else os.environ.get("SQLITE3", "sqlite3"), parser)
    assert [report["case"] for report in reports] == [case.name for case in cases()]
    assert len(reports) == 5
    assert all(report["model_status"] == "KERNEL_CHECKED_CONCRETE_ASSERTIONS" for report in reports)
    assert all(report["translation_status"] == "PRODUCTION_PIPELINE" for report in reports)
    case = cases()[0]
    before = starting_schema(parse(parser, schema_sql(case.before).encode(), "schema.sql"))
    migration = statements(parse(parser, case.migration.encode(), "migration.sql"))
    falsely_empty = replace(case, after=(replace(case.after[0], rows=()), case.after[1]))
    with TemporaryDirectory() as directory:
        proof = Path(directory) / "LostRows.lean"
        generated = schema_inputs(before) + sql_inputs(before, migration).removeprefix("import SchemaInputs\n")
        proof.write_text(generated + assertions(falsely_empty))
        rejected = subprocess.run(["lake", "env", "lean", str(proof)], cwd=ROOT,
                                  text=True, capture_output=True, timeout=30)
    assert rejected.returncode != 0, "False empty-target expectation received an accepted proof"
    assert "false" in rejected.stdout.lower(), rejected.stdout + rejected.stderr
    return reports


if __name__ == "__main__":
    print(json.dumps(main(), indent=2))
