"""Reading frozen corpora in the judge (`judge.records`), ADR 0011.

The judge must read sharded corpora (v4, v5, synthetic workload) in manifest order with their
shared snapshots put back, and give the subject nothing that SQLite observed after the start.
"""

import gzip
import json
from pathlib import Path

import pytest

from judge.records import corpus_records, subject_input

EMPTY = {"schema": [], "tables": []}
"""An empty database view."""
FULL = {"schema": [], "tables": [{"name": "t"}]}
"""A view with one table, enough to tell snapshots apart."""


def shard(path: Path, records: list[dict[str, object]]) -> None:
    """Write one gzip-compressed JSON-lines shard, the fixture form of a sharded corpus."""
    path.parent.mkdir(parents=True, exist_ok=True)
    with gzip.open(path, "wt") as stream:
        stream.writelines(json.dumps(record) + "\n" for record in records)


def stored(name: str) -> dict[str, object]:
    """A record in shared snapshot storage, where views refer to the pool by digest, to test
    that the judge puts the snapshots back."""
    return {"name": name, "snapshotStorageVersion": 1, "snapshots": {"e": EMPTY, "f": FULL},
            "initial": {"visible": {"snapshot": "e"}, "persisted": {"snapshot": "e"}, "transactionOpen": False},
            "trace": [{"sql": "x;", "visible": {"snapshot": "f"}, "persisted": {"snapshot": "e"},
                       "transactionOpen": True, "primaryCode": 0}],
            "migrationSql": "x;"}


@pytest.mark.unit
def test_shards_in_manifest_order_with_snapshots_expanded(tmp_path: Path) -> None:
    """`corpus_records`: shards come in manifest order, and each view is the pooled snapshot."""
    shard(tmp_path / "shards/b.jsonl.gz", [stored("first")])
    shard(tmp_path / "shards/a.jsonl.gz", [stored("second"), stored("third")])
    (tmp_path / "manifest.json").write_text(json.dumps({"shards": [{"path": "shards/b.jsonl.gz"},
                                                                    {"path": "shards/a.jsonl.gz"}]}))
    records = list(corpus_records(tmp_path))
    assert [record["name"] for record in records] == ["first", "second", "third"]
    assert records[0]["initial"]["visible"] == EMPTY and records[0]["trace"][0]["visible"] == FULL
    assert "snapshots" not in records[0] and "snapshotStorageVersion" not in records[0]


@pytest.mark.unit
def test_subject_input_holds_nothing_observed_after_the_start(tmp_path: Path) -> None:
    """`subject_input`: the trace's observations, codes and SQL do not reach the subject."""
    shard(tmp_path / "shards/a.jsonl.gz", [stored("only")])
    (tmp_path / "manifest.json").write_text(json.dumps({"shards": [{"path": "shards/a.jsonl.gz"}]}))
    given = subject_input(next(corpus_records(tmp_path)))
    assert set(given) == {"name", "nativeVersion", "profile", "sourceId", "initialSchemaSql", "initialRows",
                          "migrationSql"}


@pytest.mark.unit
def test_subject_input_holds_the_clock_of_each_statement(tmp_path: Path) -> None:
    """`subject_input`: a record of a controlled clock gives the subject the clock value of
    each executed statement, an input, and still nothing observed."""
    record = stored("clocked")
    record["trace"][0]["clockUnixMilliseconds"] = 1735689600000
    shard(tmp_path / "shards/a.jsonl.gz", [record])
    (tmp_path / "manifest.json").write_text(json.dumps({"shards": [{"path": "shards/a.jsonl.gz"}]}))
    given = subject_input(next(corpus_records(tmp_path)))
    assert given["clockUnixMilliseconds"] == [1735689600000]
    assert set(given) == {"name", "nativeVersion", "profile", "sourceId", "initialSchemaSql", "initialRows",
                          "migrationSql", "clockUnixMilliseconds"}


@pytest.mark.unit
def test_a_line_that_is_not_a_record_names_its_place(tmp_path: Path) -> None:
    """`corpus_records`: a malformed line is refused with its file and line number."""
    shard(tmp_path / "cases.jsonl.gz", [])
    with gzip.open(tmp_path / "cases.jsonl.gz", "wt") as stream:
        stream.write("[]\n")
    with pytest.raises(ValueError, match=r"cases\.jsonl\.gz:1: a record is not a JSON object"):
        list(corpus_records(tmp_path))
