"""Review records keep the transaction observer and the ordinary shard transport."""

from copy import deepcopy
from pathlib import Path

import pytest

from conformance.authored_cases import definitions as historical_definitions, records
from conformance.authored_boundaries import definitions as historical_boundaries
from conformance.authored_review import definitions
from conformance.case_format import Json
from conformance.corpus import load, native_replay
from conformance.corpus_shards import write
from conformance.native_storage import CASE_BYTE_LIMIT, serialized

pytestmark = [pytest.mark.integration, pytest.mark.conformance, pytest.mark.requires_native("sqlite3")]


@pytest.fixture(scope="module")
def reviewed() -> list[dict[str, Json]]:
    """Acquire only the three new cases; the existing executor bounds each native call at five seconds."""
    return records(definitions())


def test_deferred_foreign_key_commit_boundaries(reviewed: list[dict[str, Json]]) -> None:
    """The observer keeps the transaction open and records visible and persisted state apart."""
    repaired, rejected = reviewed[:2]
    for record in (repaired, rejected):
        assert all(event["transactionOpen"] for event in record["trace"][:3])
        assert all(event["persisted"] == record["initial"]["visible"] for event in record["trace"][:3])
    commit = repaired["trace"][4]
    assert not commit["transactionOpen"] and commit["visible"] == commit["persisted"]
    assert commit["persisted"] != repaired["initial"]["visible"]
    failure = rejected["trace"][-1]
    assert failure["transactionOpen"]
    assert failure["visible"] == rejected["trace"][2]["visible"]
    assert failure["persisted"] == rejected["initial"]["visible"]
    assert failure["visible"] != failure["persisted"]


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
