"""Replay literal catalog defaults through SQL parsing, INSERT, output comparison and kernel proofs."""

from copy import deepcopy
from pathlib import Path

import pytest

from conformance.authored_queries import QueryCase, records
from conformance.model_check import compiled_many, prove
from conformance.native_replay import prepare
from conformance.record_parser import runtime_library

pytestmark = [pytest.mark.integration, pytest.mark.conformance, pytest.mark.kernel,
              pytest.mark.requires_lean, pytest.mark.requires_native("parser-library", "sqlite3")]

LITERALS = ["NULL", "7", "1.5", "'7'", "'λ'", "X'00ff'", "-9223372036854775808", "TRUE", '"true"', "x'00FF'", "- 7", "[true]", "`true`"]
"""Default syntax covers each storage class, a signed boundary and quoted boolean spelling."""


@pytest.mark.parametrize("affinity", ["INTEGER", "NUMERIC", "REAL", "TEXT", "BLOB"])
def test_literal_catalog_defaults(affinity: str, runtime_root: Path, tmp_path: Path) -> None:
    """Catalog admission and INSERT agree with native rows, affinity conversions and NOT NULL failures."""
    cases = [QueryCase(f"default-{affinity}-{index}",
        f"CREATE TABLE t(id BLOB, added {affinity} DEFAULT {literal});",
        "INSERT INTO t(id) VALUES(7),(8) RETURNING *;", (), ("default", "omitted", affinity))
        for index, literal in enumerate(LITERALS)]
    cases.extend([
        QueryCase(f"nonnull-{affinity}", f"CREATE TABLE t(id BLOB, added {affinity} NOT NULL DEFAULT 7);",
                  "INSERT INTO t(id) VALUES(7) RETURNING *;", (), ("default", "not-null")),
        QueryCase(f"null-failure-{affinity}", f"CREATE TABLE t(id BLOB, added {affinity} NOT NULL DEFAULT NULL);",
                  "INSERT INTO t(id) VALUES(7) RETURNING *;", (), ("default", "not-null", "failure")),
        QueryCase(f"explicit-{affinity}", f"CREATE TABLE t(id BLOB, added {affinity} DEFAULT 7);",
                  "INSERT INTO t(id,added) VALUES(7,NULL) RETURNING *;", (), ("default", "explicit")),
        QueryCase(f"hex-error-{affinity}", f"CREATE TABLE t(id BLOB, added {affinity} DEFAULT 0x1ffffffffffffffff);",
                  "INSERT INTO t(id) VALUES(7);", (), ("default", "prepare-error")),
    ])
    library = runtime_library(runtime_root)
    prepared = []
    for record in records(cases, part="column-defaults"):
        case, error = prepare(record, library)
        assert case is not None, (record["name"], error)
        prepared.append(case)
    answers = compiled_many(prepared, runtime_root, emit_lean=True)
    assert len(answers) == len(cases)
    for index, answer in enumerate(answers):
        assert answer["verdict"] == "AGREE", (cases[index].name, answer)
        prove(answer["caseLean"], runtime_root, tmp_path / f"Default{index}.lean", case=prepared[index])


def test_changed_default_spelling_is_detected(runtime_root: Path, tmp_path: Path) -> None:
    """The catalog comparison detects changed default text even when decoded blob bytes are equal."""
    definition = QueryCase("default-spelling-mutation", "CREATE TABLE t(v BLOB DEFAULT X'00ff');",
                           "SELECT v FROM t;", (), ("default", "mutation"))
    record = next(iter(records([definition], part="column-defaults")))
    case, error = prepare(record, runtime_library(runtime_root))
    assert case is not None, error
    changed = deepcopy(case)
    changed["schema"][0]["createTable"]["columns"][0]["constraints"][0]["default"]["sourceText"] = "x'00FF'"
    original, mutated = compiled_many([case, changed], runtime_root, emit_lean=True)
    assert original["verdict"] == "AGREE", original
    assert mutated["verdict"] == "DISAGREE", mutated
    prove(mutated["caseLean"], runtime_root, tmp_path / "ChangedDefault.lean", case=changed, expected=False)
