"""Connect actual SQL parsing/translation to native observations and Lean kernel assertions."""

import json
from pathlib import Path
import subprocess
import sys
from tempfile import TemporaryDirectory

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

from migration_check.sql_model import schema_inputs, sql_inputs
from migration_check.sql_tree import parse
from migration_check.translate import starting_schema, statements
from model_assertions import assertions
from model_cases import cases, schema_sql
from model_native import check, query
from native_fixture import SOURCE_ID


def run(native: str, parser: Path) -> list[dict[str, object]]:
    """Expected observations originate in project fixtures, never from run or transition."""
    reports: list[dict[str, object]] = []
    with TemporaryDirectory() as directory:
        folder = Path(directory)
        version = query(native, folder / "pin.db", "SELECT sqlite_version() AS version,sqlite_source_id() AS source;")
        assert version == [{"version": "3.51.0", "source": SOURCE_ID}], version
        options = query(native, folder / "pin.db", "PRAGMA compile_options;")
        assert {"compile_options": "MAX_COLUMN=2000"} in options
        assert {"compile_options": "DQS=0"} in options
        for case in cases():
            before = starting_schema(parse(parser, schema_sql(case.before).encode(), case.name + "/schema.sql"))
            migration = statements(parse(parser, case.migration.encode(), case.name + "/migration.sql"))
            generated = schema_inputs(before) + sql_inputs(before, migration).removeprefix("import SchemaInputs\n")
            report = check(native, folder / (case.name + ".db"), case)
            proof = folder / (case.name + ".lean")
            proof.write_text(generated + "\n" + assertions(case))
            # The 2,000-column kernel check exceeds 30s on hosted macOS; the
            # collector still bounds the complete comparison suite to 180s.
            checked = subprocess.run(["lake", "env", "lean", str(proof)], cwd=ROOT,
                                     text=True, capture_output=True, timeout=90)
            if checked.returncode:
                raise AssertionError((case.name, checked.stdout, checked.stderr))
            assert "sorryAx" not in checked.stdout and "Lean.ofReduceBool" not in checked.stdout
            report.update({"grammar_status": "PARSED", "translation_status": "PRODUCTION_PIPELINE",
                           "model_status": "KERNEL_CHECKED_CONCRETE_ASSERTIONS",
                           "model_evidence": checked.stdout.strip()})
            reports.append(report)
    return reports


if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit("usage: model_check.py SQLITE3 SQLITE_PARSER")
    print(json.dumps(run(sys.argv[1], Path(sys.argv[2])), indent=2))
