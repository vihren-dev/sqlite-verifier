"""Complete shard loading retains evidence, independent snapshots and ordered refusals across processes."""

from collections.abc import Iterator
from concurrent.futures import Executor, ProcessPoolExecutor, ThreadPoolExecutor
from copy import deepcopy
import gzip
import hashlib
import json
from multiprocessing import get_context
from pathlib import Path

import pytest

from conformance.case_format import Json
from conformance.corpus import load
from conformance.corpus_shards import write
from conformance.execution_profile import measured_profile
from conformance.native_connection import Connection, library_path, load_library
from conformance.native_record import record_sql
from conformance.native_storage import CASE_BYTE_LIMIT, CaseSizeLimit, serialized
from conformance.native_workers import load_development_corpus

pytestmark = [pytest.mark.integration, pytest.mark.conformance, pytest.mark.requires_native("sqlite3")]


@pytest.fixture(params=["thread", "spawn"])
def executor(request: pytest.FixtureRequest) -> Iterator[Executor]:
    """Use real caller-owned backends, including worker exception transport."""
    selected = (ThreadPoolExecutor(max_workers=2) if request.param == "thread" else
                ProcessPoolExecutor(max_workers=2, mp_context=get_context("spawn")))
    with selected:
        yield selected


@pytest.fixture
def corpus(tmp_path: Path) -> Path:
    """Freeze two independently named real native observations under one exact profile."""
    connection = Connection(load_library(library_path()), tmp_path / "profile.db")
    try:
        profile = measured_profile(connection, name="loading-worker")
    finally:
        connection.close()
    original = record_sql("CREATE TABLE t(v BLOB); INSERT INTO t VALUES(X'00ff');",
                          "SELECT v FROM t;", name="first", outputs=True, profile=profile)
    shards = []
    for name in ("first", "second"):
        record = deepcopy(original)
        record.update(name=name, part="upstream", upstream={"file": name + ".test"})
        shards.append((name + ".test", "upstream", [record]))
    directory = tmp_path / "corpus"
    write(directory, shards)
    return directory


def rebind(directory: Path, index: int, record: dict[str, Json]) -> dict[str, Json]:
    """Make a damaged logical record pass its transport digests so validation reaches the actual fault."""
    manifest = json.loads((directory / "manifest.json").read_text())
    shard = manifest["shards"][index]
    payload = serialized(record) + b"\n"
    (directory / shard["path"]).write_bytes(gzip.compress(payload, mtime=0))
    shard["casesSha256"] = hashlib.sha256(payload).hexdigest()
    manifest["casesSha256"] = hashlib.sha256(b"".join(gzip.decompress(
        (directory / item["path"]).read_bytes()) for item in manifest["shards"])).hexdigest()
    (directory / "manifest.json").write_bytes(serialized(manifest))
    return manifest


def stored_record(directory: Path, index: int) -> dict[str, Json]:
    """Read one fixture's actual shared-storage record before deliberate corruption."""
    manifest = json.loads((directory / "manifest.json").read_text())
    return json.loads(gzip.decompress((directory / manifest["shards"][index]["path"]).read_bytes()))


def test_complete_parallel_load_matches_serial(corpus: Path, executor: Executor) -> None:
    """All ordered records and profiles match; nested mutations cannot cross observations or input files."""
    expected = load(corpus)
    before = {str(path): path.read_bytes() for path in corpus.rglob('*') if path.is_file()}
    actual = load(corpus, executor=executor)
    assert serialized(actual[0]) == serialized(expected[0]) and actual[1] == expected[1]
    actual[1][0]["initial"]["visible"]["tables"][0]["rows"].clear()
    assert actual[1][0]["initial"]["persisted"] == expected[1][0]["initial"]["persisted"]
    assert actual[1][1] == expected[1][1]
    assert {str(path): path.read_bytes() for path in corpus.rglob('*') if path.is_file()} == before


def test_earlier_snapshot_failure_precedes_later_metadata(corpus: Path, executor: Executor) -> None:
    """Read-ahead cannot replace the first shard's snapshot refusal with a later declaration error."""
    record = stored_record(corpus, 0)
    digest = record["initial"]["visible"]["snapshot"]
    record["snapshots"][digest]["tables"].clear()
    manifest = rebind(corpus, 0, record)
    manifest["shards"][1]["snapshotStorageVersion"] = 99
    (corpus / "manifest.json").write_bytes(serialized(manifest))
    for selected in (None, executor):
        with pytest.raises(ValueError, match="Native snapshot digest or content differs"):
            load(corpus, executor=selected)


def test_size_limit_survives_worker_transport(corpus: Path, executor: Executor) -> None:
    """A worker preserves the exact canonical oversize, limit and refusal class."""
    record = stored_record(corpus, 0)
    record["padding"] = "x" * CASE_BYTE_LIMIT
    expected = len(serialized(record))
    rebind(corpus, 0, record)
    with pytest.raises(CaseSizeLimit) as failure:
        load(corpus, executor=executor)
    assert failure.value.byte_count == expected and failure.value.limit == CASE_BYTE_LIMIT


def test_duplicate_names_precede_later_metadata(corpus: Path, executor: Executor) -> None:
    """Global case-name checks remain before errors from later declared shards."""
    record = stored_record(corpus, 1)
    record["name"] = "first"
    manifest = rebind(corpus, 1, record)
    manifest["shards"].append({"snapshotStorageVersion": 99})
    (corpus / "manifest.json").write_bytes(serialized(manifest))
    for selected in (None, executor):
        with pytest.raises(ValueError, match="Duplicate corpus case name"):
            load(corpus, executor=selected)


def test_development_helper_uses_complete_loading(corpus: Path) -> None:
    """The bounded development convenience returns the full serial primitive's evidence."""
    assert load_development_corpus(corpus) == load(corpus)
