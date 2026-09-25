"""Validate fresh Atuin receipts without merging finite payload and runner claims."""
import hashlib
from pathlib import Path

from coverage_evidence import structured

TARGET_SHA256 = "3e998a7f7df2cdcc4593e3a8b0a4e3cc7da3f798869021e27638793ef17c589e"
SOURCE_ID = "2024-05-23 13:25:27 96c92aba00c8375bc32fafcdf12429c58bd8aabfcadab6683e35bbb9cdebf19e"
PAYLOAD_CASES = ["history-0-rows", "history-1-rows", "history-3-rows"]
RUNNER_CASES = ["success", "timing_authorizer_failure"]
ALLOWED_AXIOMS = {"propext", "Classical.choice", "Quot.sound"}


def axioms_match(value: object, names: set[str]) -> bool:
    """Only the exact audited theorem set and kernel-allowed axioms count."""
    return (isinstance(value, dict) and set(value) == names and all(
        isinstance(items, list) and all(isinstance(item, str) for item in items)
        and set(items) <= ALLOWED_AXIOMS for items in value.values()))


def receipt_matches(root: Path, row: dict[str, object], payload: bool) -> bool:
    """Fresh stdout must name the actual retained trace/proof bytes, never a fallback file."""
    name = str(row["case"])
    if payload:
        count = name.split("-")[1]
        folder = root / "build/atuin-model-payload"
        native, proof = folder / f"native-{count}.json", folder / f"Payload{count}.lean"
    else:
        folder = root / "build/atuin-runner-model"
        native, proof = folder / f"{name}.json", folder / f"{name}.lean"
    try:
        return (row.get("target_sql_sha256") == TARGET_SHA256
                and row.get("native_trace_sha256") == hashlib.sha256(native.read_bytes()).hexdigest()
                and row.get("proof_sha256") == hashlib.sha256(proof.read_bytes()).hexdigest())
    except OSError:
        return False


def payload_matches(row: dict[str, object]) -> bool:
    """Payload evidence cannot stand in for readiness or full runner correspondence."""
    return (row.get("scope") == "payload-history-and-schema"
            and row.get("native_status") == "REAL_SQLX_RUNNER_MATCHED_INDEPENDENT_EXPECTATIONS"
            and row.get("model_status") == "KERNEL_CHECKED_CONCRETE_ASSERTIONS"
            and row.get("grammar_profile") == "3.46.0" and row.get("native_source_id") == SOURCE_ID
            and row.get("full_runner_relation") == "NOT_YET_COMPARED"
            and row.get("non_history_model_rows") == "abstracted empty; payload does not inspect them"
            and axioms_match(row.get("axioms"), {"checkedHistory", "checkedConformance"}))


def runner_matches(row: dict[str, object]) -> bool:
    """A schema-preserving injected error is never promoted to an unmodified-profile claim."""
    configuration = ("unmodified runner" if row["case"] == "success" else "authorizer-fault-instrumented")
    statistics = row.get("statistics_rows")
    return (row.get("scope") == "complete captured tables, physical rows, metadata and statistics"
            and row.get("grammar_profile") == "3.46.0" and row.get("native_source_id") == SOURCE_ID
            and row.get("model_status") == "KERNEL_CHECKED_PROFILE_EXECUTES"
            and row.get("native_configuration") == configuration
            and row.get("unmodified_profile_failure_claim") is False
            and row.get("metadata_rowids") == {"before":list(range(1,7)), "post_close":list(range(1,8))}
            and isinstance(statistics, dict) and set(statistics) == {"before", "post_close"}
            and all(isinstance(rows, dict) and set(rows) == {"sqlite_stat1", "sqlite_stat4"}
                    and all(type(count) is int and count >= 0 for count in rows.values())
                    for rows in statistics.values())
            and axioms_match(row.get("axioms"), {"checkedTrace", "checkedReady", "before_conforms"}))


def scope_report(root: Path, check: dict[str, object], *, payload: bool) -> dict[str, object]:
    """Malformed, duplicate, missing or failed receipts leave comparison counts unknown."""
    rows = structured(check)
    expected = PAYLOAD_CASES if payload else RUNNER_CASES
    complete = (isinstance(rows, list) and len(rows) == len(expected)
                and all(isinstance(row, dict) for row in rows)
                and [row.get("case") for row in rows] == expected
                and all(row.get("schema_objects") == 10 and receipt_matches(root, row, payload)
                        and (payload_matches(row) if payload else runner_matches(row)) for row in rows))
    if check["status"] == "PASSED" and not complete:
        check.update(status="FAILED", diagnostic="Atuin case identities, scope or receipt hashes differ")
    report: dict[str, object] = {
        "profile":"3.46.0", "status":check["status"], "case_denominator":len(expected),
        "completed_matching_cases":len(expected) if complete else None,
        "observed_discrepancies":0 if complete else None,
        "universal_native_refinement":"NOT_PROVED", "cases":rows,
        "scope":"payload history/schema only" if payload else "complete finite SQLx runner traces"}
    if not payload:
        report.update(unmodified_native_case_denominator=1, fault_instrumented_case_denominator=1,
                      unmodified_native_failure_coverage="NOT_ESTABLISHED")
    return report
