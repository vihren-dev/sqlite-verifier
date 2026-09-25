"""Compare supplied example SQL with independent expectations using pinned native SQLite."""
import hashlib
import json
from pathlib import Path
import subprocess
from tempfile import TemporaryDirectory

from atuin_sql_fixture import OLD_COLUMNS, history_seed, native_rows

ROOT = Path(__file__).resolve().parents[1]
CASES = ("history-empty", "history-singleton", "history-three-rows",
         "metadata-negative-rowids-null-keys", "metadata-max-rowid-random", "transaction-abort-rollback")
SOURCE_ID = "2024-05-23 13:25:27 96c92aba00c8375bc32fafcdf12429c58bd8aabfcadab6683e35bbb9cdebf19e"
CHECKSUM = "5376BB3DDC6A9956652BFF2B9807B64A83219A4201D1F1E7DE9F7760F2507F191856AE5F549A7613253D1284C9A1B988"
VERSION = 20260709214605


def snapshot(stage: str, *, shell: bool = False) -> str:
    """Read every old stored class/byte and all schema/metadata fields on the same connection."""
    cells = ",".join(f"typeof({name}),quote({name}),hex({name})" for name in OLD_COLUMNS)
    added = ", 'shell', (SELECT json_group_array(json_array(rowid,shell)) FROM (SELECT rowid,* FROM history ORDER BY rowid))" if shell else ""
    return f"""SELECT json_object('stage','{stage}',
      'history',(SELECT json_group_array(json_array(rowid,{cells})) FROM (SELECT rowid,* FROM history ORDER BY rowid)),
      'metadata',(SELECT json_group_array(json_array(rowid,version,description,installed_on,success,hex(checksum),execution_time))
                  FROM (SELECT rowid,* FROM _sqlx_migrations ORDER BY rowid)),
      'schema',(SELECT json_group_array(json_array(type,name,tbl_name,sql)) FROM (SELECT * FROM sqlite_schema ORDER BY type,name)),
      'integrity',(SELECT integrity_check FROM pragma_integrity_check){added});\n"""


def metadata_seed(kind: str) -> str:
    """Use ordinary existing records, including nullable non-rowid BIGINT primary keys."""
    if kind == "empty":
        return ""
    keys = [(-5, "NULL"), (-2, "NULL")] if kind == "negative" else [
        (2**63-1 if kind == "maximum" else 1, str(VERSION) if kind == "duplicate" else "1")]
    return "\n".join(f"INSERT INTO _sqlx_migrations VALUES ({version},'earlier','2020-01-01 00:00:00',1,X'AB',77);\n"
        f"UPDATE _sqlx_migrations SET rowid={rowid} WHERE rowid=last_insert_rowid();"
        for rowid, version in keys)


def execute(native: str, sql: str, *, failure: bool = False) -> list[dict[str, object]]:
    """CLI streaming input continues after an expected ABORT only when explicitly requested."""
    with TemporaryDirectory(prefix="atuin-sql-") as directory:
        result = subprocess.run([native, "-batch", str(Path(directory)/"history.db")],
            input=(".bail off\n" if failure else ".bail on\n") + ".mode list\n" + sql,
            capture_output=True, text=True, timeout=5)
    if failure:
        assert result.returncode != 0 and "UNIQUE constraint failed: _sqlx_migrations.version" in result.stderr, result.stderr
    else:
        assert result.returncode == 0, result.stderr
    return [json.loads(line) for line in result.stdout.splitlines() if line]


def schema_change(before: list[list[object]], after: list[list[object]]) -> None:
    """Only history's definition may change, and it must append the declared nullable shell."""
    assert len(before) == len(after) == 8
    assert [(row[0],row[1],row[2]) for row in before] == [(row[0],row[1],row[2]) for row in after]
    for old, new in zip(before, after, strict=True):
        if old[1] == "history":
            assert str(new[3]).count(", shell text") == 1
            assert str(new[3]).replace(", shell text", "", 1) == old[3]
        else:
            assert old == new


def run(native: str) -> list[dict[str, object]]:
    """Native observations are not mislabeled as checked model assertions or framework evidence."""
    identity = subprocess.run([native, "-batch", ":memory:", "SELECT sqlite_version(),sqlite_source_id();"],
                              capture_output=True, text=True, check=True, timeout=5)
    assert identity.stdout.strip() == "3.46.0|" + SOURCE_ID, identity.stdout
    schema_bytes = (ROOT/"examples/atuin/schema.sql").read_bytes()
    schema = schema_bytes.decode("utf-8")
    migration_bytes = (ROOT/"examples/atuin/migration.sql").read_bytes()
    migration = migration_bytes.decode("utf-8")
    reports = []
    for name, count, kind in zip(CASES, (0,1,3,3,1,3), ("empty","ordinary","ordinary","negative","maximum","duplicate"), strict=True):
        initial = schema + history_seed(count) + metadata_seed(kind) + snapshot("before")
        if kind == "duplicate":
            assert migration.count("COMMIT;") == 1
            sql = initial + migration.split("COMMIT;")[0] + snapshot("failed", shell=True) + "ROLLBACK;\n" + snapshot("rolled_back")
            before, failed, rolled_back = execute(native, sql, failure=True)
            assert failed["history"] == before["history"] == native_rows(count)
            assert failed["metadata"] == before["metadata"]
            assert before["integrity"] == failed["integrity"] == "ok"
            assert failed["shell"] == [[row[0],None] for row in native_rows(count)]
            schema_change(before["schema"], failed["schema"])
            assert {k:v for k,v in rolled_back.items() if k != "stage"} == {k:v for k,v in before.items() if k != "stage"}
        else:
            before, after = execute(native, initial + migration + snapshot("after", shell=True))
            assert before["history"] == after["history"] == native_rows(count)
            assert before["integrity"] == after["integrity"] == "ok"
            assert after["shell"] == [[row[0],None] for row in native_rows(count)]
            old = before["metadata"]
            new = [row for row in after["metadata"] if row[1] == VERSION]
            assert len(new) == 1 and new[0][1:] == [VERSION,"shell","2026-09-25 00:00:00",1,CHECKSUM,1000000]
            assert [row for row in after["metadata"] if row[1] != VERSION] == old
            if kind == "maximum":
                assert 0 < new[0][0] < 2**63-1  # SQLite's documented random fresh-positive fallback.
            else:
                assert new[0][0] == max((row[0] for row in old), default=0)+1
            schema_change(before["schema"], after["schema"])
        reports.append({"case":name, "status":"NATIVE_SQL_EXPECTATIONS_PASSED", "profile":"3.46.0",
            "model_status":"NOT_COMPARED_BY_THIS_TEST", "schema_objects":8,
            "domain":"random-rowid boundary outside deterministic model" if kind=="maximum" else "ordinary SQL",
            "schema_sha256":hashlib.sha256(schema_bytes).hexdigest(),
            "migration_sha256":hashlib.sha256(migration_bytes).hexdigest()})
    return reports
