"""Compare real SQLx history outcomes to kernel-checked production payload semantics."""
from __future__ import annotations

import json
from pathlib import Path
import subprocess
import sys
from tempfile import TemporaryDirectory

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from migration_check.sql_model import sql_inputs
from migration_check.profiles import ExecutionProfile, MigrationIdentity
from migration_check.sql_tree import parse
from migration_check.translate import starting_schema, statements
from atuin_cases import COUNTS, native_rows
from atuin_model_assertions import assertions, audit_axioms

CAPTURE = ROOT / "conformance/atuin_capture"


def run(parser: Path) -> list[dict[str, object]]:
    """No full-runner relation is inferred from this explicitly payload-scoped comparison."""
    before_sql = (CAPTURE / "before.sql").read_bytes()
    after_sql = (CAPTURE / "after.sql").read_bytes()
    sql = (CAPTURE / "migrations/20260709214605_shell.sql").read_bytes()
    before = starting_schema(parse(parser, before_sql, "captured-before.sql", "3.46.0"))
    expected_schema = starting_schema(parse(parser, after_sql, "captured-after.sql", "3.46.0"))
    script = statements(parse(parser, sql, "original-migration.sql", "3.46.0"))
    expected_history = next(table for table in expected_schema if table.name == "history")
    expected_capture = json.loads((CAPTURE / "capture.json").read_text())
    previous = tuple(MigrationIdentity(row["version"], bytes.fromhex(row["checksum_hex"]))
                     for row in expected_capture["before"]["metadata"])
    selected = ExecutionProfile("3.46.0", 20260709214605, b"shell", previous)
    generated = sql_inputs(before, script, selected, sql)
    reports: list[dict[str, object]] = []
    evidence = ROOT / "build/atuin-model-payload"
    evidence.mkdir(parents=True, exist_ok=True)
    with TemporaryDirectory(prefix="atuin-model-") as directory:
        folder = Path(directory)
        for count in COUNTS:
            result = subprocess.run([str(ROOT / "build/atuin-cargo-target/debug/adversarial"),
                str(folder / f"history-{count}.db"), str(CAPTURE / "migrations"), "success", str(count)],
                capture_output=True, text=True, timeout=30, check=True)
            native = json.loads(result.stdout)
            (evidence / f"native-{count}.json").write_text(result.stdout)
            for field in ("sqlite_version", "sqlite_source_id", "pragmas", "runtime_limits"):
                assert native["profile"][field] == expected_capture["profile"][field], field
            flags = [flag for flag in native["profile"]["compile_options"] if not flag.startswith("COMPILER=")]
            expected_flags = [flag for flag in expected_capture["profile"]["compile_options"]
                              if not flag.startswith("COMPILER=")]
            assert flags == expected_flags, "Native semantic compile flags changed"
            assert native["error"] is None, native["error"]
            for key in ("history_before", "history_after", "post_close_history"):
                assert native[key] == native_rows(count), (count, key, native[key])
            assert native["shell_nulls"] == count and native["integrity_check"] == "ok"
            for stage in ("before", "after", "post_close"):
                # Root pages may vary with data allocation; every definition remains bound.
                actual = [{k: row[k] for k in ("type", "name", "table", "sql")}
                          for row in native[stage]["schema"]]
                expected = [{k: row[k] for k in ("type", "name", "table", "sql")}
                            for row in expected_capture[stage]["schema"]]
                assert actual == expected, (count, stage)
            proof = folder / f"Payload{count}.lean"
            proof.write_text(generated + assertions(count, expected_history))
            (evidence / proof.name).write_text(proof.read_text())
            checked = subprocess.run(["lake", "env", "lean", str(proof)], cwd=ROOT,
                                     capture_output=True, text=True, timeout=45)
            if checked.returncode:
                raise AssertionError((count, checked.stdout, checked.stderr))
            axioms = audit_axioms(checked.stdout, {"checkedHistory", "checkedConformance"})
            reports.append({"case": f"history-{count}-rows", "scope": "payload-history-and-schema",
                "native_status": "REAL_SQLX_RUNNER_MATCHED_INDEPENDENT_EXPECTATIONS",
                "model_status": "KERNEL_CHECKED_CONCRETE_ASSERTIONS",
                "grammar_profile": "3.46.0", "schema_objects": 10,
                "native_source_id": native["profile"]["sqlite_source_id"],
                "full_runner_relation": "NOT_YET_COMPARED",
                "non_history_model_rows": "abstracted empty; payload does not inspect them",
                "axioms": axioms})
    return reports


if __name__ == "__main__":
    report = json.dumps(run(ROOT / "build/sqlite-parser-3.46.0"), indent=2) + "\n"
    (ROOT / "build/atuin-model-payload.json").write_text(report)
    print(report, end="")
