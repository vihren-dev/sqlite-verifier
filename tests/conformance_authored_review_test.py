"""Review boundaries retain deferred transaction errors and exact numeric observations."""

from copy import deepcopy
from pathlib import Path

import pytest

from conformance.authored_cases import definitions as historical_definitions, records
from conformance.authored_boundaries import definitions as historical_boundaries
from conformance.authored_review import definitions
from conformance.case_format import Json
from conformance.corpus import load, native_replay
from conformance.corpus_shards import write
from conformance.native_connection import Row
from conformance.native_replay import decode_rows
from conformance.native_storage import CASE_BYTE_LIMIT, serialized

pytestmark = [pytest.mark.integration, pytest.mark.conformance, pytest.mark.requires_native("sqlite3")]


@pytest.fixture(scope="module")
def reviewed() -> list[dict[str, Json]]:
    """Acquire only the three new cases; the existing executor bounds each native call at five seconds."""
    return records(definitions())


def table_values(observation: dict[str, Json], name: str) -> list[Row]:
    """Read integer fixture rows by table name independently of schema ordering."""
    table = next(table for table in observation["tables"] if table["name"] == name)
    return decode_rows([row["values"] for row in table["rows"]])


def test_deferred_foreign_key_commit_boundaries(reviewed: list[dict[str, Json]]) -> None:
    """Repair permits commit; failure keeps pending child state while the observer sees no writes."""
    repaired, rejected = reviewed[:2]
    for record in (repaired, rejected):
        assert record["profile"]["foreignKeys"] and record["profile"]["transactionMode"] == "immediate"
        assert record["profile"]["clock"] == "excluded"
        assert all(event["transactionOpen"] for event in record["trace"][:3])
        assert all(event["primaryCode"] == 0 for event in record["trace"][:3])
        assert decode_rows(record["trace"][2]["rows"]) == [((1, 10), (1, 1))]
        assert all(event["persisted"] == record["initial"]["visible"] for event in record["trace"][:3])
    assert len(repaired["trace"]) == 6
    commit = repaired["trace"][4]
    assert commit["primaryCode"] == commit["extendedCode"] == 0 and not commit["transactionOpen"]
    assert commit["visible"] == commit["persisted"]
    assert table_values(commit["persisted"], "parent") == [((1, 1),)]
    assert table_values(commit["persisted"], "child") == [((1, 10), (1, 1))]
    assert decode_rows(repaired["trace"][5]["rows"]) == [((1, 10), (1, 1))]
    assert len(rejected["trace"]) == 4
    failure = rejected["trace"][-1]
    assert failure["sql"].strip() == "COMMIT;"
    assert failure["primaryCode"] == 19 and failure["extendedCode"] == 787
    assert failure["transactionOpen"] and failure["changes"] is None
    assert failure["visible"] == rejected["trace"][2]["visible"]
    assert failure["persisted"] == rejected["initial"]["visible"]
    assert table_values(failure["visible"], "child") == [((1, 10), (1, 1))]
    assert table_values(failure["visible"], "parent") == []
    assert table_values(failure["persisted"], "child") == []


def test_cast_outputs_preserve_exact_real_bits(reviewed: list[dict[str, Json]]) -> None:
    """A decimal prefix becomes exact REAL123.5, distinct from integer123 and REAL123.75."""
    numeric = reviewed[2]
    event = numeric["trace"][0]
    assert numeric["profile"]["transactionMode"] == "deferred"
    assert len(numeric["trace"]) == 1 and event["primaryCode"] == event["extendedCode"] == 0
    assert event["columns"] == ["as_real", "as_numeric", "as_integer", "arithmetic"]
    assert decode_rows(event["rows"]) == [
        ((2, 0x405EE00000000000), (2, 0x405EE00000000000), (1, 123), (2, 0x405EF00000000000))]
    assert decode_rows([event["parameters"]]) == [
        ((3, b"123.5abc"), (3, b"123.5abc"), (3, b"123abc"), (3, b"123.5abc"))]
    assert event["visible"] == event["persisted"] == numeric["initial"]["visible"]


def test_review_shard_load_and_fresh_replay(reviewed: list[dict[str, Json]], tmp_path: Path) -> None:
    """New v5 evidence uses the ordinary transport without mutating old catalogs or observations."""
    assert len(historical_definitions()) == 43 and len(historical_boundaries()) == 23
    assert len({record["name"] for record in reviewed}) == len(reviewed) == 3
    assert all(len(serialized(record)) <= CASE_BYTE_LIMIT for record in reviewed)
    directory = tmp_path / "review-corpus"
    manifest = write(directory, [("review-boundaries", "boundary-interaction", reviewed)], corpus_version=5)
    loaded_manifest, loaded = load(directory)
    assert loaded_manifest == manifest and loaded == reviewed
    assert manifest["corpusVersion"] == 5 and manifest["recordedCases"] == 3
    assert manifest["shards"][0]["source"] == "review-boundaries"
    native_replay(loaded)
    changed = deepcopy(loaded[2])
    changed["trace"][0]["rows"][0][0]["real"]["bits"] = str(0x405EE00000000001)
    with pytest.raises(ValueError, match="Native replay changed"):
        native_replay([changed])
