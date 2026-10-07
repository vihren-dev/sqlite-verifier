"""Stored transaction evidence is digest-bound and checked by fresh native replay."""

from copy import deepcopy
import gzip
import hashlib
from pathlib import Path

import pytest

from conformance.authored_cases import records
from conformance.authored_transactions import definitions
from conformance.case_format import Json
from conformance.corpus import load, native_replay
from conformance.native_storage import expanded_record, shared_record
from conformance.transaction_evidence import CORPUS_VERSION, EVIDENCE_KIND, publish

ROOT = Path(__file__).resolve().parents[1]
EVIDENCE = ROOT / "reports/20261006-grouped-immediate-transactions"
pytestmark = [pytest.mark.integration, pytest.mark.conformance, pytest.mark.requires_native("sqlite3")]


@pytest.fixture(scope="module")
def acquired() -> list[dict[str, Json]]:
    """Acquire new evidence with five-second native statement deadlines."""
    return records(definitions())


def test_publication_load_and_fresh_replay(acquired: list[dict[str, Json]], tmp_path: Path) -> None:
    """The ordinary shared-snapshot transport preserves measured records and refuses replacement."""
    directory = tmp_path / "transactions"
    manifest = publish(directory)
    loaded_manifest, loaded = load(directory)
    assert loaded_manifest == manifest and loaded == acquired
    assert manifest["evidenceKind"] == EVIDENCE_KIND
    assert manifest["recordedCases"] == 5 and manifest["corpusVersion"] == CORPUS_VERSION
    assert manifest["definitionsSha256"] == hashlib.sha256(
        (ROOT / "conformance/authored_transactions.py").read_bytes()).hexdigest()
    native_replay(loaded)
    with pytest.raises(ValueError, match="output already exists.*choose a new directory"):
        publish(directory)


def test_published_evidence_matches_current_definitions(acquired: list[dict[str, Json]]) -> None:
    """The retained additions have exact native/profile bindings and replay through fresh connections."""
    manifest, retained = load(EVIDENCE)
    assert retained == acquired
    assert manifest["evidenceKind"] == EVIDENCE_KIND
    assert manifest["corpusVersion"] == CORPUS_VERSION
    assert manifest["definitionsSha256"] == hashlib.sha256(
        (ROOT / "conformance/authored_transactions.py").read_bytes()).hexdigest()
    native_replay(retained)


@pytest.mark.parametrize("damage", ["commit-boundary", "savepoint-boundary", "committed-snapshot"])
def test_changed_boundaries_or_committed_state_fail_replay(acquired: list[dict[str, Json]], damage: str) -> None:
    """Fresh replay detects false publication and transaction closure even when transport is valid."""
    changed = deepcopy(acquired[2] if damage == "savepoint-boundary" else acquired[0])
    if damage == "commit-boundary":
        changed["trace"][6]["transactionOpen"] = True
    elif damage == "savepoint-boundary":
        changed["trace"][7]["transactionOpen"] = False
    else:
        changed["trace"][3]["persisted"] = deepcopy(changed["trace"][3]["visible"])
    assert expanded_record(shared_record(changed)) == changed
    with pytest.raises(ValueError, match="Native replay changed"):
        native_replay([changed])


def test_changed_shared_snapshot_fails_storage_validation(acquired: list[dict[str, Json]]) -> None:
    """Changing a pool value cannot reuse its original digest before any replay occurs."""
    stored = deepcopy(shared_record(acquired[0]))
    snapshot = next(iter(stored["snapshots"].values()))
    snapshot["tables"] = []
    with pytest.raises(ValueError, match="snapshot digest or content differs"):
        expanded_record(stored)


def test_changed_stored_boundary_fails_corpus_binding(tmp_path: Path) -> None:
    """A changed transaction flag cannot keep the manifest's original stored-case digest."""
    directory = tmp_path / "transactions"
    manifest = publish(directory)
    shard = directory / manifest["shards"][0]["path"]
    payload = gzip.decompress(shard.read_bytes())
    damaged = payload.replace(b'"transactionOpen":false', b'"transactionOpen":true', 1)
    assert damaged != payload
    shard.write_bytes(gzip.compress(damaged, mtime=0))
    with pytest.raises(ValueError, match="Corpus shard digest mismatch"):
        load(directory)
