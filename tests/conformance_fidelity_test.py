"""Fidelity triage binds every historical refusal and preserves independent truth."""

from collections import Counter
from copy import deepcopy
import gzip
import hashlib
import json
from pathlib import Path

import pytest

from conformance.corpus import native_replay
from conformance.native_record import record_sql
from conformance.upstream_fidelity import check_results
from conformance.upstream_selection import candidate_reasons

pytestmark = [pytest.mark.conformance]


@pytest.mark.unit
def test_ledger_covers_every_historical_fidelity_refusal() -> None:
    """Cause labels cover the exact frozen denominator and bind their original observations."""
    root = Path(__file__).resolve().parents[1]
    summary = json.loads((root / "reports/20261001-adr5-c4-fidelity.json").read_text())
    historical = gzip.decompress((root / summary["historicalExtraction"]).read_bytes())
    assert hashlib.sha256(historical).hexdigest() == summary["historicalExtractionSha256"]
    frozen = json.loads(historical)
    artifacts = {}
    for name, field in (("causes", "ledgerSha256"), ("traces", "tracesSha256"),
                        ("mechanical", "mechanicalProofSha256"), ("bindings", "bindingProofSha256")):
        payload = gzip.decompress((root / f"reports/20261001-adr5-c4-{name}.json.gz").read_bytes())
        assert hashlib.sha256(payload).hexdigest() == summary[field]
        artifacts[name] = json.loads(payload)
    rows = artifacts["causes"]
    expected = {(file["file"], row["id"], row["occurrence"]): row["result"]
                for file in frozen["files"] for row in file.get("instances", []) if "differ" in row["result"]}
    actual = {(row["file"], row["id"], row["occurrence"]): row["result"] for row in rows}
    assert len(rows) == len(actual) == len(expected) == summary["differingCandidates"] == 143
    assert actual == expected
    assert all(row["cause"] for row in rows)
    assert Counter(row["cause"] for row in rows) == summary["causes"]
    assert summary["unmappedCandidates"] == 0
    for name, trace in artifacts["traces"].items():
        source = next(file for file in frozen["files"] if file["file"] == name)
        assert trace["sourceSha256"] == source["sha256"]
        assert trace["events"]
    for row in rows:
        if row["cause"] == "filesystem path observation: PRAGMA database_list":
            assert row["actual"][::3] == row["expected"][::3]
            assert row["actual"][1::3] == row["expected"][1::3]
            assert row["actual"][2::3] != row["expected"][2::3]
    assert len(artifacts["mechanical"]["experiments"]) == 3
    binding = artifacts["bindings"]
    assert binding["historical-unbound"]["rows"] == [["null"]]
    assert binding["typed-bound-before-BLOB"]["tclValues"] == [binding["bindingEvidence"]["TclValue"]]
    assert binding["typed-bound-before-BLOB"]["tclValues"] != binding["TclExpectedAfterBlobWrite"]


@pytest.mark.integration
@pytest.mark.requires_native("sqlite3")
@pytest.mark.parametrize("sql,expected,cause", [
    ("PRAGMA database_list", ["0", "main", "/independent/tcl/test.db"], "filesystem path observation"),
    ("-- metadata\nPRAGMA main.\"database_list\";", ["0", "main", "/tcl/test.db"], "filesystem path observation"),
    ("PRAGMA lock_status", ["main", "unlocked", "temp", "closed"], "testfixture-only lock metadata"),
    ("PRAGMA database_list", ["0", "other", "/tcl/test.db"], "prefix results differ from Tcl execution$"),
    ("SELECT 'PRAGMA database_list'", ["wrong"], "prefix results differ from Tcl execution$"),
])
def test_proven_metadata_mismatch_has_a_narrow_cause(sql: str, expected: list[str], cause: str) -> None:
    """Name only proven path/build differences; ordinary row differences stay distinct."""
    record = record_sql([sql], "SELECT 1", name="metadata-cause")
    original = deepcopy(record)
    candidate = {"prefixCodes": [0], "prefixResults": [expected], "prefixHelpers": ["eval"],
                 "commands": ["SELECT 1"], "helpers": ["eval"], "codes": [0], "results": [["1"]]}
    with pytest.raises(ValueError, match=cause):
        check_results(record, candidate)
    assert record == original
    native_replay([record])


@pytest.mark.integration
@pytest.mark.requires_native("sqlite3")
@pytest.mark.parametrize("prefix", [False, True])
def test_missing_testfixture_module_keeps_native_error(prefix: bool) -> None:
    """A missing echo module gets a named mismatch, retaining the real native error."""
    sql = "CREATE VIRTUAL TABLE e USING echo(t)"
    record = record_sql(["CREATE TABLE t(v)", sql] if prefix else ["CREATE TABLE t(v)"],
                        "SELECT 1" if prefix else sql, name="module-cause")
    original = deepcopy(record)
    candidate = {"prefixCodes": [0, 0] if prefix else [0],
                 "prefixResults": [[], []] if prefix else [[]], "codes": [0]}
    with pytest.raises(ValueError, match="testfixture-only virtual-table module: echo"):
        check_results(record, candidate)
    assert record == original
    native_replay([record])


@pytest.mark.unit
def test_uncaptured_tcl_bindings_are_excluded_without_guessing_values() -> None:
    """Named variables in setup or SQL cannot silently become native NULL bindings."""
    candidate = {"exclusions": [], "failed": False, "codes": [0],
                 "prefix": [{"reopen": True}, "INSERT INTO t VALUES($dots)"],
                 "commands": ["SELECT :value, @other, '$literal', \"$column\" /* $comment */"]}
    assert set(candidate_reasons(candidate, selected=0, limit=1)) == {
        "implicit Tcl parameter binding: $dots", "implicit Tcl parameter binding: :value",
        "implicit Tcl parameter binding: @other"}
    candidate["prefix"] = []
    candidate["commands"] = ["SELECT '$literal', \"$column\" /* $comment */"]
    assert candidate_reasons(candidate, selected=0, limit=1) == []
    candidate["commands"] = ["SELECT :; SELECT 1::int"]
    assert candidate_reasons(candidate, selected=0, limit=1) == []
    candidate["commands"] = ["SELECT 1 /* $comment"]
    assert candidate_reasons(candidate, selected=0, limit=1) == []
    candidate["commands"] = ["SELECT :name::scope(key), $💫(x), @x$y /* $comment"]
    assert set(candidate_reasons(candidate, selected=0, limit=1)) == {
        "implicit Tcl parameter binding: :name::scope(key)", "implicit Tcl parameter binding: $💫(x)",
        "implicit Tcl parameter binding: @x$y"}


@pytest.mark.integration
@pytest.mark.requires_native("sqlite3")
def test_explicit_typed_parameters_remain_recordable() -> None:
    """Rejecting untraced Tcl bindings leaves the native typed-parameter primitive available."""
    value = b"." * 40
    record = record_sql("CREATE TABLE t(v)", "INSERT INTO t VALUES(?); SELECT v FROM t",
        name="explicit-binding", outputs=True, parameters=[((3, value),), ()])
    assert record["trace"][-1]["rows"] == [[{"text": {"bytes": list(value)}}]]
    native_replay([record])


@pytest.mark.integration
@pytest.mark.requires_native("sqlite3")
def test_native_parameter_names_survive_ordering_probes() -> None:
    """SQLite's full named-slot spelling stays intact through numbered window probes."""
    record = record_sql("", "SELECT :name::scope(key) AS v UNION ALL SELECT $💫(x) AS v "
        "ORDER BY v LIMIT @limit$slot /* $comment", name="parameter-spelling", outputs=True,
        parameters=[((1, 2), (1, 1), (1, 1))])
    assert record["trace"][0]["rows"] == [[{"integer": {"value": 1}}]]
    assert record["trace"][0]["groups"][0]["count"] == 1
    native_replay([record])
