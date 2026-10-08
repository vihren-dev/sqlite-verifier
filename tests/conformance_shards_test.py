"""New sharded corpora retain native truth and reject altered transport or declarations."""

from copy import deepcopy
from dataclasses import replace
import gzip
import hashlib
import json
from pathlib import Path

import pytest

from conformance.case_format import Json
from conformance.corpus import load, native_replay
from conformance.corpus_shards import source_path, write
from conformance.execution_profile import measured_profile, profile_from_wire
from conformance.native_connection import Connection, library_path, load_library
from conformance.native_record import record_sql
from conformance.native_storage import CASE_BYTE_LIMIT, CaseSizeLimit, serialized, shared_record

ROOT = Path(__file__).resolve().parents[1]
pytestmark = [pytest.mark.integration, pytest.mark.conformance, pytest.mark.requires_native("sqlite3")]


@pytest.fixture
def cases(tmp_path: Path) -> list[dict[str, Json]]:
    """Acquire independent native cases with two actual profile identities and typed parameters."""
    connection = Connection(load_library(library_path()), tmp_path / "measure.db")
    try:
        profile = measured_profile(connection, name="shards-first", transaction_mode="immediate")
    finally:
        connection.close()
    acquired = [record_sql("CREATE TABLE t(v BLOB);", "BEGIN IMMEDIATE; INSERT INTO t VALUES(?);"
        "SELECT v FROM t ORDER BY v; COMMIT;", name=name, outputs=True,
        parameters=[(), ((4, b"\x00\xff"),), (), ()], profile=selected)
        for name, selected in (("first", profile), ("second", replace(profile, name="shards-second")))]
    acquired[0]["part"] = "boundary-interaction"
    acquired[1].update(part="upstream", upstream={"file": "b.test"})
    return acquired


def corpus(directory: Path, cases: list[dict[str, Json]]) -> dict[str, Json]:
    """Keep shard order different from case-name order so sorting cannot replace the manifest."""
    write(directory, [("b.test", "upstream", [cases[1]]),
                      ("a.sql", "boundary-interaction", [cases[0]])],
          metadata={"sourceFiles": ["b.test", "a.sql"]})
    return json.loads((directory / "manifest.json").read_text())


def save_manifest(directory: Path, manifest: dict[str, Json]) -> None:
    """Change only declarations when testing their independent trust boundary."""
    (directory / "manifest.json").write_bytes(serialized(manifest))


def replace_payload(directory: Path, manifest: dict[str, Json], values: list[dict[str, Json]]) -> None:
    """Rebind outer hashes so malformed case evidence must fail its own checks."""
    shard = manifest["shards"][0]
    payload = b"".join(serialized(value) + b"\n" for value in values)
    (directory / shard["path"]).write_bytes(gzip.compress(payload, mtime=0))
    shard["casesSha256"] = hashlib.sha256(payload).hexdigest()
    combined = b"".join(gzip.decompress((directory / item["path"]).read_bytes()) for item in manifest["shards"])
    manifest["casesSha256"] = hashlib.sha256(combined).hexdigest()
    save_manifest(directory, manifest)


def test_round_trip_order_profiles_and_legacy(cases: list[dict[str, Json]], tmp_path: Path) -> None:
    """Loading uses declared shard order, preserves full native observations and keeps v1/v2 readable."""
    directory = tmp_path / "frozen"
    manifest = corpus(directory, cases)
    loaded_manifest, records = load(directory)
    assert loaded_manifest == manifest and records == [cases[1], cases[0]]
    assert [shard["source"] for shard in manifest["shards"]] == ["b.test", "a.sql"]
    assert manifest["recordedCases"] == 2 and manifest["nativeVersion"] == 4
    assert manifest["sourceFiles"] == ["b.test", "a.sql"]
    native_replay(records)
    assert load(ROOT / "conformance/corpus-v1")[0]["recordedCases"] == 177
    assert load(ROOT / "conformance/corpus-v2")[0]["recordedCases"] == 183
    with pytest.raises(ValueError, match="already exists"):
        corpus(directory, cases)
    empty = tmp_path / "already-empty"
    empty.mkdir()
    with pytest.raises(ValueError, match="already exists"):
        corpus(empty, cases)


@pytest.mark.parametrize("field", ["shardStorageVersion", "caseFormatVersion", "nativeVersion", "snapshotStorageVersion"])
@pytest.mark.parametrize("version", [True, 99])
def test_unknown_or_boolean_root_versions(cases: list[dict[str, Json]], tmp_path: Path,
                                          field: str, version: int) -> None:
    """A corpus identity cannot upgrade its acquisition or storage declarations implicitly."""
    directory = tmp_path / "frozen"
    manifest = corpus(directory, cases)
    manifest[field] = version
    save_manifest(directory, manifest)
    with pytest.raises(ValueError, match="format"):
        load(directory)


@pytest.mark.parametrize("damage", ["root-count", "shard-count", "root-digest", "shard-digest",
    "duplicate-path", "duplicate-source", "root-profile", "shard-profile", "extra-profile", "duplicate-profile",
    "shard-format", "root-version", "part-label", "source-label"])
def test_manifest_mismatches(cases: list[dict[str, Json]], tmp_path: Path, damage: str) -> None:
    """Counts, paths, source identities and exact profiles are all independent bindings."""
    directory = tmp_path / "frozen"
    manifest = corpus(directory, cases)
    first, second = manifest["shards"]
    if damage.endswith("count"):
        (manifest if damage.startswith("root") else first)["recordedCases"] = True
    elif damage.endswith("digest"):
        (manifest if damage.startswith("root") else first)["casesSha256"] = "0" * 64
    elif damage == "duplicate-path":
        second["path"] = first["path"]
    elif damage == "duplicate-source":
        second["source"], second["part"] = first["source"], first["part"]
    elif damage.endswith("profile"):
        target = manifest if damage != "shard-profile" else first
        if damage in {"extra-profile", "duplicate-profile"}:
            target["executionProfiles"].append({**target["executionProfiles"][0],
                "name": "unused" if damage == "extra-profile" else target["executionProfiles"][0]["name"]})
        else:
            target["executionProfiles"][0]["foreignKeys"] = True
    elif damage == "root-version":
        manifest["corpusVersion"] = True
    elif damage in {"part-label", "source-label"}:
        first["part" if damage == "part-label" else "source"] = "wrong"
    else:
        first["nativeVersion"] = 3
    save_manifest(directory, manifest)
    with pytest.raises(ValueError):
        load(directory)


@pytest.mark.parametrize("path", ["/outside.json", "../outside.json", "shards/./0000.jsonl.gz", "shards//0000.jsonl.gz", "shards/0000.jsonl.gz/"])
def test_noncanonical_paths_refused(cases: list[dict[str, Json]], tmp_path: Path, path: str) -> None:
    """Paths cannot escape, alias declarations, or use ambiguous empty components."""
    directory = tmp_path / "frozen"
    manifest = corpus(directory, cases)
    manifest["shards"][0]["path"] = path
    save_manifest(directory, manifest)
    with pytest.raises(ValueError, match="path"):
        load(directory)


def test_symlink_escape_and_duplicate_alias(cases: list[dict[str, Json]], tmp_path: Path) -> None:
    """Resolved identities detect an in-root alias, while outside targets remain inaccessible."""
    directory = tmp_path / "frozen"
    manifest = corpus(directory, cases)
    (directory / "alias.gz").symlink_to(directory / manifest["shards"][0]["path"])
    manifest["shards"][1]["path"] = "alias.gz"
    save_manifest(directory, manifest)
    with pytest.raises(ValueError, match="Duplicate.*path"):
        load(directory)
    (directory / "escape.sql").symlink_to(tmp_path / "measure.db")
    with pytest.raises(ValueError, match="escapes"):
        source_path(directory, "escape.sql")


@pytest.mark.parametrize("damage", ["duplicate-name", "native-version", "storage-version", "output", "oversized"])
def test_corruption_after_rebinding(cases: list[dict[str, Json]], tmp_path: Path, damage: str) -> None:
    """Recomputed transport digests cannot conceal wrong formats, aliases or oversized logical cases."""
    directory = tmp_path / "frozen"
    manifest = corpus(directory, cases)
    broken = deepcopy(cases[1])
    if damage == "duplicate-name":
        broken["name"] = cases[0]["name"]
    elif damage == "output":
        broken["trace"][0]["columnCount"] = True
    elif damage == "oversized":
        broken = record_sql("CREATE TABLE t(v BLOB); INSERT INTO t VALUES(zeroblob(20000));",
            "SELECT count(*) FROM t;" * 12, name="second", outputs=True,
            profile=profile_from_wire(cases[1]["profile"]))
        broken.update(part="upstream", upstream={"file": "b.test"})
        assert len(serialized(broken)) > CASE_BYTE_LIMIT
    stored = shared_record(broken, byte_limit=None)
    if damage == "oversized":
        assert len(serialized(stored)) < CASE_BYTE_LIMIT
    if damage.endswith("version"):
        stored["nativeVersion" if damage == "native-version" else "snapshotStorageVersion"] = True
    replace_payload(directory, manifest, [stored])
    with pytest.raises(ValueError) as failure:
        load(directory)
    if damage == "oversized":
        assert isinstance(failure.value, CaseSizeLimit) and failure.value.byte_count == len(serialized(broken))


def test_writer_validates_every_case_before_creating_output(cases: list[dict[str, Json]], tmp_path: Path) -> None:
    """A bad later shard or reserved metadata field cannot partially freeze an earlier valid shard."""
    directory = tmp_path / "frozen"
    cases[0]["padding"] = "x" * CASE_BYTE_LIMIT
    with pytest.raises(CaseSizeLimit):
        corpus(directory, cases)
    assert not directory.exists()
    with pytest.raises(ValueError, match="overrides"):
        write(directory, [("b.test", "upstream", [cases[1]])], metadata={"recordedCases": 8})
    assert not directory.exists()
