"""Kernel-check complete observed runner states, distinguishing explicit fault instrumentation."""
from __future__ import annotations

import json
import hashlib
from pathlib import Path
import subprocess
import sys
from tempfile import TemporaryDirectory

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from migration_check.profiles import ExecutionProfile, MigrationIdentity
from migration_check.sql_model import sql_inputs
from migration_check.sql_tree import parse
from migration_check.translate import starting_schema, statements
from atuin_cases import native_rows
from atuin_model_assertions import audit_axioms
from atuin_trace_assertions import assertions

CAPTURE = ROOT / "conformance/atuin_capture"


def run() -> list[dict[str, object]]:
    """Every metadata and statistics row participates in the complete concrete relation."""
    parser = ROOT / "build/sqlite-parser-3.46.0"
    provenance = json.loads((CAPTURE / "provenance.json").read_text())
    assert {path.name for path in (CAPTURE / "migrations").iterdir()} == set(provenance["migration_sha256"])
    assert len(provenance["migration_sha256"]) == 7
    for name, expected in provenance["migration_sha256"].items():
        assert hashlib.sha256((CAPTURE / "migrations" / name).read_bytes()).hexdigest() == expected, name
    baseline = json.loads((CAPTURE / "capture.json").read_text())
    before = starting_schema(parse(parser, (CAPTURE / "before.sql").read_bytes(), "before.sql", "3.46.0"))
    after = starting_schema(parse(parser, (CAPTURE / "after.sql").read_bytes(), "after.sql", "3.46.0"))
    sql = (CAPTURE / "migrations/20260709214605_shell.sql").read_bytes()
    script = statements(parse(parser, sql, "migration.sql", "3.46.0"))
    previous = tuple(MigrationIdentity(row["version"], bytes.fromhex(row["checksum_hex"]))
                     for row in baseline["before"]["metadata"])
    selected = ExecutionProfile("3.46.0", 20260709214605, b"shell", previous)
    generated = sql_inputs(before, script, selected, sql)
    evidence = ROOT / "build/atuin-runner-model"
    evidence.mkdir(parents=True, exist_ok=True)
    reports = []
    for scenario in ("success", "timing_authorizer_failure"):
        with TemporaryDirectory(prefix="atuin-full-trace-") as directory:
            result = subprocess.run([str(ROOT / "build/atuin-cargo-target/debug/adversarial"),
                str(Path(directory) / "history.db"), str(CAPTURE / "migrations"), scenario],
                capture_output=True, text=True, timeout=30, check=True)
        native = json.loads(result.stdout)
        (evidence / f"{scenario}.json").write_text(result.stdout)
        for key in ("history_before", "history_after", "post_close_history"):
            assert native[key] == native_rows(3), key
        assert native["shell_nulls"] == 3 and native["integrity_check"] == "ok"
        for field in ("sqlite_version", "sqlite_source_id", "pragmas", "runtime_limits"):
            assert native["profile"][field] == baseline["profile"][field], field
        flags = [flag for flag in native["profile"]["compile_options"] if not flag.startswith("COMPILER=")]
        expected_flags = [flag for flag in baseline["profile"]["compile_options"]
                          if not flag.startswith("COMPILER=")]
        assert flags == expected_flags, "Native semantic compile flags changed"
        for stage in ("before", "after", "post_close"):
            assert native[stage]["schema"] == baseline[stage]["schema"], stage
        if scenario == "success":
            assert native["error"] is None and native["instrumentation"] is None
        else:
            assert "not authorized" in native["error"]
            assert native["instrumentation"] == {"kind":"SQLITE_AUTHORIZER",
                "denied_table":"_sqlx_migrations", "denied_column":"execution_time", "denied_updates":1}
            assert native["post_close"]["metadata"][-1]["execution_time"] == -1
        proof = evidence / f"{scenario}.lean"
        proof.write_text(generated + assertions(before, after, native,
                         timing_failure=scenario != "success"))
        checked = subprocess.run(["lake", "env", "lean", str(proof)], cwd=ROOT,
                                 capture_output=True, text=True, timeout=60)
        if checked.returncode:
            raise AssertionError((scenario, checked.stdout, checked.stderr))
        axioms = audit_axioms(checked.stdout, {"checkedTrace", "checkedReady", "before_conforms"})
        assert len(native["before"]["metadata"]) == 6 and len(native["post_close"]["metadata"]) == 7
        reports.append({"case":scenario,"model_status":"KERNEL_CHECKED_PROFILE_EXECUTES",
            "scope":"complete captured tables, physical rows, metadata and statistics",
            "native_configuration":"unmodified runner" if scenario=="success" else "authorizer-fault-instrumented",
            "unmodified_profile_failure_claim":False,"schema_objects":10,"axioms":axioms,
            "metadata_rowids": {stage:[row["rowid"] for row in native[stage]["metadata"]]
                                for stage in ("before", "post_close")},
            "statistics_rows": {stage:{name:len(rows) for name,rows in native[stage]["statistics"].items()}
                                for stage in ("before", "post_close")},
            "native_trace_sha256":hashlib.sha256(result.stdout.encode()).hexdigest(),
            "proof_sha256":hashlib.sha256(proof.read_bytes()).hexdigest(),
            "target_sql_sha256":hashlib.sha256(sql).hexdigest()})
    return reports


if __name__ == "__main__":
    report = json.dumps(run(), indent=2) + "\n"
    (ROOT / "build/atuin-runner-model.json").write_text(report)
    print(report, end="")
