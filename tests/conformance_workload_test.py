"""External directory commands bind complete SQL inventories and native output evidence."""

import json
from pathlib import Path
import shutil
import subprocess
import sys

import pytest

from conformance.case_format import Json
from conformance.corpus import load
from conformance.corpus_shards import write
from conformance.native_record import record_sql
from conformance.native_connection import Connection, library_path, load_library
from conformance.native_replay import decode_rows
from conformance.workload import bound_records, record, report
from conformance.workload_inputs import load_inputs

ROOT = Path(__file__).resolve().parents[1]
pytestmark = [pytest.mark.integration, pytest.mark.conformance,
              pytest.mark.requires_native("sqlite3", "sqlite-parser")]


def copied_inputs(tmp_path: Path) -> Path:
    """Give corruption tests independent source files and a measured pinned profile."""
    directory = tmp_path / "input"
    shutil.copytree(ROOT / "conformance/synthetic-workload", directory)
    return directory


def inventory(directory: Path) -> dict[str, Json]:
    """Read the user-editable inventory for targeted negative cases."""
    return json.loads((directory / "workload.json").read_text())


def save_inventory(directory: Path, value: dict[str, Json]) -> None:
    """Keep test edits explicit so their binding failures remain attributable."""
    (directory / "workload.json").write_text(json.dumps(value))


def command(arguments: list[str]) -> None:
    """Run the actual public module entrypoint with a short process timeout."""
    subprocess.run([sys.executable, "-m", "conformance.workload", *arguments],
                   cwd=ROOT, check=True, capture_output=True, text=True, timeout=45)


def test_directory_commands_record_replay_and_combined_progress(tmp_path: Path, runtime_root: Path) -> None:
    """Parameters, transaction state, trigger rows and cascade counts survive the CLI path."""
    source = copied_inputs(tmp_path)
    frozen = tmp_path / "frozen"
    command(["record", str(source), "--output", str(frozen)])
    manifest, records = bound_records(source, frozen)
    assert manifest["recordedCases"] == 2 and manifest["nativeReplayPassed"]
    trace = records[0]["trace"]
    assert [event["changes"] for event in trace] == [None, 1, 2, None, 1, None, None, None]
    assert decode_rows(trace[1]["rows"]) == [((1, 2), (3, b"a"))]
    assert trace[1]["parameters"] == inventory(source)["cases"][0]["parameters"][1]
    assert trace[5]["rows"] == []
    assert decode_rows(trace[6]["rows"]) == [((1, 2),), ((1, 2),)]
    assert trace[1]["transactionOpen"] and not trace[-1]["transactionOpen"]
    assert all(not table["rows"] for table in trace[1]["persisted"]["tables"])
    assert records[1]["trace"][0]["columns"] == ["missing_id", "label"]
    assert records[1]["trace"][0]["rows"] == []
    replay_output = tmp_path / "replay.json"
    command(["replay", str(source), "--corpus", str(frozen), "--runtime-root", str(runtime_root),
             "--output", str(replay_output)])
    assert json.loads(replay_output.read_text())["counts"] == {"MODEL_UNSUPPORTED": 2}
    generic = tmp_path / "generic"
    evidence = record_sql("", "SELECT 1;", name="generic-query", outputs=True, profile=load_inputs(source).profile)
    evidence.update({"part": "boundary-interaction", "features": ["select"]})
    write(generic, [("neutral", "boundary-interaction", [evidence])])
    combined_output = tmp_path / "combined.json"
    command(["progress", str(source), "--corpus", str(frozen), "--generic", str(generic),
             "--runtime-root", str(runtime_root), "--output", str(combined_output)])
    combined = json.loads(combined_output.read_text())
    assert combined["denominator"] == 3 and combined["counts"] == {"MODEL_UNSUPPORTED": 3}
    assert combined["generic"]["denominator"] == 1 and combined["workload"]["denominator"] == 2


@pytest.mark.parametrize("file", ["workload.json", "profile.json", "schema.sql", "transaction.sql"])
def test_changed_source_files_refuse_replay(tmp_path: Path, runtime_root: Path, file: str) -> None:
    """Even harmless formatting changes break the exact frozen input binding."""
    source = copied_inputs(tmp_path)
    record(source, tmp_path / "frozen")
    with (source / file).open("a") as stream:
        stream.write("\n")
    with pytest.raises(ValueError, match="source inventory differs"):
        report(source, tmp_path / "frozen", runtime_root)


def test_inventory_refuses_missing_or_unexecuted_inputs(tmp_path: Path) -> None:
    """Failures cannot silently omit a SQL tail, parameter occurrence, or unlisted file."""
    source = copied_inputs(tmp_path)
    original = inventory(source)
    for sql, parameters in (("INSERT INTO parent VALUES(1,NULL); SELECT 7;", [[], []]),
                            ("INSERT INTO parent VALUES(1,NULL);", [[], []]),
                            ("-- no statement", [])):
        value = {**original, "cases": [{"name": "incomplete", "sql": "transaction.sql",
                 "parameters": parameters, "features": ["constraint-failure"]}, original["cases"][1]]}
        save_inventory(source, value)
        (source / "transaction.sql").write_text(sql)
        with pytest.raises(ValueError, match="unexecuted"):
            record(source, tmp_path / "never-frozen")
        assert not (tmp_path / "never-frozen").exists()
    save_inventory(source, original)
    (source / "extra.sql").write_text("SELECT 1;")
    with pytest.raises(ValueError, match="every SQL file"):
        load_inputs(source)


def test_inventory_refuses_malformed_parameters_and_escaping_paths(tmp_path: Path) -> None:
    """Typed cells and file paths are validated before native execution."""
    source = copied_inputs(tmp_path)
    for cell in ({"integer": {"value": True}}, {"integer": {"value": 1, "ignored": 2}},
                 {"blob": {"bytes": [256]}}):
        value = inventory(source)
        value["cases"][1]["parameters"] = [[cell]]
        save_inventory(source, value)
        with pytest.raises(ValueError, match="cell|encoding"):
            load_inputs(source)
    value = inventory(source)
    value["cases"][1]["parameters"] = [[{"integer": {"value": 1}}]]
    value["cases"][1]["sql"] = "../outside.sql"
    save_inventory(source, value)
    with pytest.raises(ValueError, match="path"):
        load_inputs(source)


def test_failed_last_statement_is_complete_evidence(tmp_path: Path, runtime_root: Path) -> None:
    """A fully reached constraint failure remains evidence, including trailing comments."""
    source = copied_inputs(tmp_path)
    value = inventory(source)
    value["cases"][0]["parameters"] = [[]]
    save_inventory(source, value)
    (source / "transaction.sql").write_text("INSERT INTO parent VALUES(1,NULL); -- final failure\n;")
    record(source, tmp_path / "frozen")
    _, records = load(tmp_path / "frozen")
    assert records[0]["trace"][0]["primaryCode"] == 19
    assert report(source, tmp_path / "frozen", runtime_root)["counts"] == {"MODEL_UNSUPPORTED": 2}


def test_setup_file_boundaries_and_executable_setup_binding(tmp_path: Path) -> None:
    """EOF comments keep separate setup calls; executable setup must equal the bound source."""
    source = copied_inputs(tmp_path)
    value = inventory(source)
    value["cases"][1]["setup"] = ["fixture.sql"]
    save_inventory(source, value)
    with (source / "schema.sql").open("a") as stream:
        stream.write("-- EOF comment")
    (source / "fixture.sql").write_text("INSERT INTO parent VALUES(99,'fixture');")
    record(source, tmp_path / "frozen")
    _, records = bound_records(source, tmp_path / "frozen")
    assert decode_rows(records[1]["trace"][0]["rows"]) == [((1, 99), (3, b"fixture"))]
    altered = []
    inputs = load_inputs(source)
    for case in inputs.cases:
        evidence = record_sql(case.setup + "\n; INSERT INTO audit VALUES(99);", case.sql,
            name=case.name, outputs=True, parameters=case.parameters, profile=inputs.profile)
        evidence.update(setupSql=case.setup, part="workload", features=case.features)
        altered.append(evidence)
    write(tmp_path / "altered", [("workload", "workload", altered)], metadata={
        "workloadInventory": {"formatVersion": 1, "manifest": "workload.json", "sources": inputs.sources}})
    with pytest.raises(ValueError, match="membership or profile"):
        bound_records(source, tmp_path / "altered")


def test_nul_sql_cannot_hide_unexecuted_input(tmp_path: Path) -> None:
    """All C API paths refuse NUL SQL; typed parameter data keeps its embedded NUL bytes."""
    source = copied_inputs(tmp_path)
    (source / "transaction.sql").write_text("SELECT 1;\x00SELECT 2;")
    with pytest.raises(ValueError, match="NUL"):
        record(source, tmp_path / "never-frozen")
    assert not (tmp_path / "never-frozen").exists()
    with pytest.raises(ValueError, match="NUL"):
        record_sql("CREATE TABLE t(a);\x00INSERT INTO t VALUES(1);", "SELECT 1;", name="nul-setup")
    connection = Connection(load_library(library_path()), tmp_path / "transport.db")
    try:
        for operation in (connection.query_result, connection.execute_script):
            with pytest.raises(ValueError, match="NUL"):
                operation("SELECT 1;\x00SELECT 2;")
        assert connection.query_result("SELECT ?;", ((3, b"a\x00b"),)).rows == [((3, b"a\x00b"),)]
    finally:
        connection.close()
