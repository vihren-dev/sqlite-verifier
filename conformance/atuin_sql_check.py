"""Check old application data preservation using supplied SQL and pinned native SQLite."""
import hashlib
import json
from pathlib import Path
import subprocess
from tempfile import TemporaryDirectory

from atuin_sql_fixture import COUNTS, OLD_COLUMNS, history_seed, native_rows

ROOT = Path(__file__).resolve().parents[1]
CASES = ("history-empty", "history-singleton", "history-three-rows")
SOURCE_ID = "2024-05-23 13:25:27 96c92aba00c8375bc32fafcdf12429c58bd8aabfcadab6683e35bbb9cdebf19e"


def snapshot() -> str:
    """Read every old stored class and byte, without anticipating an added column."""
    cells = ",".join(f"typeof({name}),quote({name}),hex({name})" for name in OLD_COLUMNS)
    return f"""SELECT json_object(
      'history',(SELECT json_group_array(json_array(rowid,{cells})) FROM (SELECT rowid,* FROM history ORDER BY rowid)),
      'integrity',(SELECT integrity_check FROM pragma_integrity_check));\n"""


def execute(native: str, sql: str) -> list[dict[str, object]]:
    """Run the exact payload and observations on a single temporary native database."""
    with TemporaryDirectory(prefix="atuin-sql-") as directory:
        result = subprocess.run([native, "-batch", str(Path(directory)/"history.db")],
            input=".bail on\n.mode list\n" + sql,
            capture_output=True, text=True, timeout=5)
    assert result.returncode == 0, result.stderr
    return [json.loads(line) for line in result.stdout.splitlines() if line]


def run(native: str) -> list[dict[str, object]]:
    """Compare old data to independent fixtures; native evidence is not a universal proof."""
    identity = subprocess.run([native, "-batch", ":memory:", "SELECT sqlite_version(),sqlite_source_id();"],
                              capture_output=True, text=True, check=True, timeout=5)
    assert identity.stdout.strip() == "3.46.0|" + SOURCE_ID, identity.stdout
    schema_bytes = (ROOT/"examples/atuin/schema.sql").read_bytes()
    migration_bytes = (ROOT/"examples/atuin/migration.sql").read_bytes()
    reports = []
    for name, count in zip(CASES, COUNTS, strict=True):
        before, after = execute(native, schema_bytes.decode("utf-8") + history_seed(count)
                                + snapshot() + migration_bytes.decode("utf-8") + snapshot())
        assert before["history"] == after["history"] == native_rows(count)
        assert before["integrity"] == after["integrity"] == "ok"
        reports.append({"case":name, "status":"NATIVE_SQL_EXPECTATIONS_PASSED", "profile":"3.46.0",
            "model_status":"NOT_COMPARED_BY_THIS_TEST", "domain":"old application data preservation",
            "schema_sha256":hashlib.sha256(schema_bytes).hexdigest(),
            "migration_sha256":hashlib.sha256(migration_bytes).hexdigest()})
    return reports
