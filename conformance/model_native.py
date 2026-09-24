"""Native comparison for project-derived cases, independent of formal model execution."""

import json
from pathlib import Path
import subprocess

from model_cases import Case, inserts_sql, quoted, schema_sql


def invoke(native: str, database: Path, sql: str) -> subprocess.CompletedProcess[str]:
    """Use a fresh pinned connection with startup scripts disabled and stop-on-error."""
    return subprocess.run([native, "-init", "/dev/null", "-batch", "-bail", "-json", str(database)],
                          input=sql, text=True, capture_output=True, timeout=5)


def query(native: str, database: Path, sql: str) -> list[dict[str, object]]:
    """Preserve JSON cell types, field order, and empty-result behavior."""
    result = invoke(native, database, sql)
    if result.returncode:
        raise AssertionError(result.stderr)
    rows: list[dict[str, object]] = json.loads(result.stdout) if result.stdout.strip() else []
    return rows


def check(native: str, database: Path, case: Case) -> dict[str, object]:
    """Compare exact logical contents and schema, including state committed before failure."""
    initialized = invoke(native, database, schema_sql(case.before) + inserts_sql(case.before))
    if initialized.returncode:
        raise AssertionError(initialized.stderr)
    migrated = invoke(native, database, case.migration)
    if case.native_error:
        assert migrated.returncode != 0 and case.native_error in migrated.stderr, migrated
    else:
        assert migrated.returncode == 0, migrated.stderr
    schema = query(native, database, "SELECT type,name FROM sqlite_schema ORDER BY name;")
    assert schema == [{"type": "table", "name": name} for name in sorted(table.name for table in case.after)]
    observations: list[dict[str, object]] = []
    for table in case.after:
        columns = query(native, database, f"PRAGMA table_info({quoted(table.name)});")
        assert [(row["name"], row["type"]) for row in columns] == list(table.columns)
        if table.rows:
            rows = query(native, database, f"SELECT rowid,* FROM {quoted(table.name)} ORDER BY rowid;")
        else:
            # A 2000-column table plus rowid exceeds SQLite's result-column limit.
            assert query(native, database, f"SELECT count(*) AS n FROM {quoted(table.name)};") == [{"n": 0}]
            rows = []
        assert [tuple(row.values()) for row in rows] == list(table.rows), (case.name, rows)
        observations.append({"table": table.name, "rows": rows, "column_count": len(columns)})
    return {"case": case.name, "native_status": "MATCHES_INDEPENDENT_EXPECTATION",
            "error": case.native_error, "observations": observations}
