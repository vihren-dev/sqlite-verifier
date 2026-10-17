"""Compare ADD COLUMN default execution and failed catalogs with both pinned SQLite engines."""

import json
from pathlib import Path

import pytest

from conformance.execution_profile import measured_profile
from conformance.model_check import compiled_many, prove_all
from conformance.native_connection import Connection, library_path
from conformance.native_library import library_binary, load_library
from conformance.native_record import record_sql
from conformance.native_replay import prepare
from conformance.record_parser import runtime_library

pytestmark = [pytest.mark.integration, pytest.mark.conformance, pytest.mark.kernel,
              pytest.mark.requires_lean, pytest.mark.requires_native("parser-library", "sqlite3", "sqlite3-3.46.0")]

LITERALS = ["NULL", "7", "1.50", "'7'", "X'00ff'", "TRUE", "[true]",
            "-9223372036854775808", "0x1ffffffffffffffff", "-0x1ffffffffffffffff"]
"""Defaults cover storage classes, source spelling and the readback/INSERT distinction."""
AFFINITIES = ["INTEGER", "NUMERIC", "REAL", "TEXT", "BLOB"]
"""Each affinity of an added column; one test covers all of them, so that the cases share one
classification and the proofs run in parallel batches."""


def added_cases(affinity: str) -> list[tuple[str, str]]:
    """The setup and SQL of the ADD COLUMN cases of one affinity."""
    empty = "CREATE TABLE t(id BLOB);"
    populated = empty + "INSERT INTO t VALUES(7),(8);"
    cases = [(populated, f"ALTER TABLE t ADD COLUMN added {affinity} DEFAULT {value}; SELECT * FROM t;")
             for value in LITERALS]
    cases.extend([
        (populated, f"ALTER TABLE t ADD COLUMN added {affinity} NOT NULL DEFAULT 7; SELECT * FROM t;"),
        (populated, f"ALTER TABLE t ADD COLUMN added {affinity} NOT NULL DEFAULT NULL;"),
        (empty, f"ALTER TABLE t ADD COLUMN added {affinity} NOT NULL DEFAULT NULL;"),
        (populated, f"ALTER TABLE t ADD COLUMN added {affinity} NOT NULL;"),
        (empty, f"ALTER TABLE t ADD COLUMN added {affinity} NOT NULL;"),
        (populated, f"BEGIN; ALTER TABLE t ADD COLUMN prefix BLOB DEFAULT 3; "
                    f"ALTER TABLE t ADD COLUMN added {affinity} NOT NULL DEFAULT NULL; COMMIT;"),
        (populated, f"BEGIN; ALTER TABLE t ADD COLUMN added {affinity} DEFAULT 7; ROLLBACK; SELECT * FROM t;"),
    ])
    return cases


@pytest.mark.parametrize("version", ["3.51.0", "3.46.0"])
def test_added_defaults_match_native(version: str, runtime_root: Path, tmp_path: Path) -> None:
    """Resolution, execution and comparison retain default values, old rows and catalogs after ADD fails."""
    binary = library_path(library_binary(version))
    connection = Connection(load_library(binary, version), tmp_path / "profile.db")
    try:
        profile = measured_profile(connection, name="added-defaults", format_version=3)
    finally:
        connection.close()
    cases = [case for affinity in AFFINITIES for case in added_cases(affinity)]
    library = runtime_library(runtime_root)
    prepared = []
    for index, (setup, sql) in enumerate(cases):
        record = record_sql(setup, sql, name=f"add-default-{index}", library=binary, outputs=True, profile=profile)
        case, error = prepare(record, library)
        assert case is not None, (sql, error)
        prepared.append(case)
    answers = compiled_many(prepared, runtime_root, emit_lean=True)
    assert len(answers) == len(cases)
    for index, answer in enumerate(answers):
        if answer["verdict"] != "AGREE":
            diagnostic = tmp_path / "disagreement.json"
            diagnostic.write_text(json.dumps({"version": version, "sql": cases[index],
                "verdict": answer["verdict"], "position": answer.get("position"),
                "case": prepared[index]}, indent=2))
            pytest.fail(f"ADD COLUMN disagrees for {cases[index][1]}; details: {diagnostic}")
    prove_all([answer["caseLean"] for answer in answers], runtime_root, tmp_path, cases=prepared, name="Added")
