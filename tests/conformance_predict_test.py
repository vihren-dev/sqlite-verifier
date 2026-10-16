"""The subject's predict command (`conformance.predict`, `conformance.predict_render`), ADR 0011.

The judge compares the subject's predictions with SQLite's recordings in SQLite's catalog
terms, so the prediction must state what SQLite reports for each table shape that the model
supports. Each declaration below is recorded by native SQLite and predicted from the record's
subject input; the judge's comparison form (`judge.catalog`) of both initial steps must be equal.
"""

import json
from pathlib import Path
import subprocess
import sys

import pytest

from conformance.native_record import record_sql
from judge.catalog import tables_form
from judge.records import subject_input

pytestmark = [pytest.mark.integration, pytest.mark.conformance,
              pytest.mark.requires_lean, pytest.mark.requires_native("parser-library", "sqlite3")]

PREDICT_TIMEOUT_SECONDS = 60
"""One predict run over one small case."""
DECLARATIONS = {
    "affinities": "CREATE TABLE t(a INTEGER, b REAL, c TEXT, d BLOB, e NUMERIC);",
    "spellings": "CREATE TABLE t(a BIGINT, b TIMESTAMP, c BOOLEAN, d);",
    "not null and default": "CREATE TABLE t(a TEXT NOT NULL, b TIMESTAMP DEFAULT CURRENT_TIMESTAMP);",
    "lower-case default": "CREATE TABLE t(a TIMESTAMP DEFAULT current_timestamp);",
    "text primary key": "CREATE TABLE t(id TEXT PRIMARY KEY, a TEXT);",
    "integer primary key that is not the row id": "CREATE TABLE t(id BIGINT PRIMARY KEY, a TEXT);",
    "unique constraint": "CREATE TABLE t(a INTEGER, b TEXT, UNIQUE(a, b));",
    "indexes": "CREATE TABLE t(a INTEGER, b TEXT); CREATE INDEX t_a ON t(a); CREATE UNIQUE INDEX t_b ON t(b);",
    "primary key constraint": "CREATE TABLE t(a TEXT, b TEXT, PRIMARY KEY(b, a));",
    "row id alias": "CREATE TABLE t(id INTEGER PRIMARY KEY, a TEXT);",
    "descending primary key": "CREATE TABLE t(id INTEGER PRIMARY KEY DESC, a TEXT);",
    "unique before descending primary key": "CREATE TABLE t(a TEXT UNIQUE PRIMARY KEY DESC, b TEXT);",
    "descending primary key before unique": "CREATE TABLE t(a TEXT PRIMARY KEY DESC UNIQUE, b TEXT);",
    "merged unique keys": "CREATE TABLE t(a TEXT UNIQUE ON CONFLICT REPLACE, b TEXT, UNIQUE(a), PRIMARY KEY(b), UNIQUE(b));",
}
"""Table shapes that resolution accepts in a schema and the model represents. A row id
alias (`INTEGER PRIMARY KEY`) has no key index; `INTEGER PRIMARY KEY DESC` is not an alias,
and its key index is descending. Constraints of one index give one index, with the direction of the first of
them."""


def predict(runtime_root: Path, *records: dict[str, object]) -> list[dict[str, object]]:
    """Run the predict command over the subject inputs of the records."""
    lines = "".join(json.dumps(subject_input(record)) + "\n" for record in records)
    result = subprocess.run([sys.executable, "-m", "conformance.predict", "--runtime", str(runtime_root)],
                            input=lines, capture_output=True, text=True, timeout=PREDICT_TIMEOUT_SECONDS, check=False)
    assert result.returncode == 0, result.stderr
    return [json.loads(line) for line in result.stdout.splitlines()]


@pytest.mark.parametrize("name", DECLARATIONS)
def test_predicted_catalog_equals_native(name: str, runtime_root: Path) -> None:
    """`VerifierConformance.Predict` and `conformance.predict_render`: the predicted initial
    catalog of a declaration is the catalog that native SQLite records."""
    record = record_sql(DECLARATIONS[name], "", name=name)
    [prediction] = predict(runtime_root, record)
    assert prediction["status"] == "predicted", prediction
    assert tables_form(prediction["steps"][0]["visible"]) == tables_form(record["initial"]["visible"])


def test_predict_command_reports_scope(runtime_root: Path) -> None:
    """`conformance.predict.main`: an admitted case is predicted with one step per executed
    statement and a start offset, including the starting rows; a refused one is out of scope
    with the frontend's reason, and a restricted one also names the restriction's stable id."""
    admitted = record_sql("CREATE TABLE t(a INTEGER); INSERT INTO t VALUES (7);", "INSERT INTO t(a) VALUES (1);",
                          name="admitted")
    refused = record_sql("CREATE TABLE t(a INTEGER);", "CREATE VIEW v AS SELECT a FROM t;", name="refused")
    restricted = record_sql("CREATE TABLE t(a INTEGER);", "SELECT abs(a) FROM t;", name="restricted")
    first, second, third = predict(runtime_root, admitted, refused, restricted)
    assert first["status"] == "predicted" and first["supported"] and len(first["steps"]) == 2
    assert first["steps"][1]["start"] == 0
    assert tables_form(first["steps"][1]["visible"]) == tables_form(admitted["trace"][0]["visible"])
    assert second["status"] == "unsupported" and second["reason"]
    assert third["status"] == "unsupported" and third["restriction"] == "unmodeled-function", third


def profiled(runtime_root: Path, name: str, setup: str = "CREATE TABLE t(a INTEGER NOT NULL);",
             migration: str = "INSERT INTO t(a) VALUES (NULL);", **settings: object) -> dict[str, object]:
    """A version 5 record, by default of a case that fails in `sqlite3_step`, under a measured
    profile with the given execution settings and a column limit lowered to 5."""
    from tempfile import TemporaryDirectory
    from conformance.execution_profile import measured_profile
    from conformance.native_connection import Connection, library_path, load_library
    from conformance.native_limits import lower_limits
    with TemporaryDirectory() as directory:
        connection = Connection(load_library(library_path()), Path(directory) / "profile.db")
        try:
            lower_limits(connection, {"columns": 5})
            profile = measured_profile(connection, name=name, format_version=3, **settings)
        finally:
            connection.close()
    return record_sql(setup, migration, name=name, outputs=True, profile=profile)


def test_profiled_records_use_their_limits_and_phases(runtime_root: Path) -> None:
    """`conformance.profile_scope.modeled_profile` and `VerifierConformance.Predict`: a record
    whose profile uses only the default execution settings is predicted under its recorded
    limits, with the error phase; one with foreign keys is out of scope, and the reason names
    the setting."""
    default, keyed = profiled(runtime_root, "default"), profiled(runtime_root, "keyed", foreign_keys=True)
    assert default["nativeVersion"] == 5 and default["trace"][0]["phase"] == "step"
    first, second = predict(runtime_root, default, keyed)
    assert first["status"] == "predicted" and first["supported"], first
    assert [step["phase"] for step in first["steps"]] == [None, "step"]
    assert first["steps"][1]["primaryCode"] == 19
    assert second["status"] == "unsupported"
    assert second["reason"].startswith("keyed: the model does not implement foreign keys")


def test_prediction_uses_the_recorded_column_limit(runtime_root: Path) -> None:
    """`VerifierConformance.Predict.predict` resolves under the recorded limits: ADD COLUMN on a
    table with 5 columns is a prepare error under the recorded limit of 5, which the default
    limit of 2,000 would accept."""
    record = profiled(runtime_root, "narrow", "CREATE TABLE t(a, b, c, d, e);", "ALTER TABLE t ADD f;")
    assert record["trace"][0]["primaryCode"] == 1 and record["trace"][0]["phase"] == "prepare"
    [prediction] = predict(runtime_root, record)
    assert prediction["status"] == "predicted" and prediction["supported"], prediction
    assert (prediction["steps"][1]["primaryCode"], prediction["steps"][1]["phase"]) == (1, "prepare")
