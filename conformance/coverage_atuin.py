"""Keep ordinary native SQL observations separate from formal proof status."""
import hashlib
from pathlib import Path

from atuin_sql_check import CASES
from coverage_evidence import structured


def sql_report(root: Path, check: dict[str, object]) -> dict[str, object]:
    """Fresh complete case identities and actual SQL hashes are mandatory; old reports are ignored."""
    rows = structured(check)
    try:
        schema = hashlib.sha256((root/"examples/atuin/schema.sql").read_bytes()).hexdigest()
        migration = hashlib.sha256((root/"examples/atuin/migration.sql").read_bytes()).hexdigest()
    except OSError:
        schema = migration = None
    complete = (schema is not None and migration is not None and isinstance(rows, list)
        and len(rows) == len(CASES) and all(isinstance(row, dict) for row in rows)
        and [row.get("case") for row in rows] == list(CASES)
        and all(row.get("status") == "NATIVE_SQL_EXPECTATIONS_PASSED"
            and row.get("profile") == "3.46.0"
            and row.get("model_status") == "NOT_COMPARED_BY_THIS_TEST"
            and row.get("schema_sha256") == schema and row.get("migration_sha256") == migration
            and row.get("domain") == "old application data preservation" for row in rows))
    if check["status"] == "PASSED" and not complete:
        check.update(status="FAILED", diagnostic="Incomplete or mismatched ordinary Atuin SQL observations")
    return {"profile":"3.46.0", "status":check["status"], "case_denominator":len(CASES),
        "completed_matching_cases":len(CASES) if complete else None,
        "observed_discrepancies":0 if complete else None,
        "model_status":"NOT_COMPARED_BY_THIS_TEST", "universal_native_refinement":"NOT_PROVED",
        "scope":"old application data preservation; not framework invocation or proof witnesses",
        "cases":rows}
