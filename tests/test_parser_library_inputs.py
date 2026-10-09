"""The parser library checks read every SQL text of both corpus formats.

These tests check `tests/parser_library_inputs.py`, which the sanitizer job and the
comparison use instead of the conformance harness loader.
"""

import gzip
import hashlib
import json
from pathlib import Path

import pytest

from tests.parser_inputs import all_inputs
from tests.parser_library_inputs import corpus_texts, read_records, write_records

pytestmark = [pytest.mark.unit, pytest.mark.parser]
CASE = {"name": "case", "migrationSql": "ALTER TABLE t ADD b;", "setupSql": "CREATE TABLE t(a);",
        "setupCommands": ["CREATE TABLE t(a);", {"reopen": True}],
        "trace": [{"sql": "SELECT 1;"}, {"changes": 0}]}
"""A case with every field that holds SQL, and a setup step and a trace event without SQL."""


def payload(cases: list[dict[str, object]]) -> bytes:
    """Return the JSON lines of the cases."""
    return b"".join(json.dumps(case).encode() + b"\n" for case in cases)


def test_single_file_and_sharded_corpora_give_the_same_texts(tmp_path: Path) -> None:
    """Both corpus layouts give the migration, setup, command and trace texts once each."""
    data = payload([CASE, {**CASE, "name": "copy"}])
    single = tmp_path / "single"
    single.mkdir()
    (single / "cases.jsonl.gz").write_bytes(gzip.compress(data))
    (single / "manifest.json").write_text(json.dumps({"casesSha256": hashlib.sha256(data).hexdigest()}))
    sharded = tmp_path / "sharded"
    (sharded / "shards").mkdir(parents=True)
    (sharded / "shards/a.jsonl.gz").write_bytes(gzip.compress(data))
    (sharded / "manifest.json").write_text(json.dumps(
        {"shards": [{"path": "shards/a.jsonl.gz", "casesSha256": hashlib.sha256(data).hexdigest()}]}))
    expected = {"ALTER TABLE t ADD b;", "CREATE TABLE t(a);", "SELECT 1;"}
    assert corpus_texts(single) == corpus_texts(sharded) == expected


def test_changed_corpus_file_is_refused(tmp_path: Path) -> None:
    """A case file that differs from its manifest digest is not read."""
    (tmp_path / "cases.jsonl.gz").write_bytes(gzip.compress(payload([CASE])))
    (tmp_path / "manifest.json").write_text(json.dumps({"casesSha256": "0" * 64}))
    with pytest.raises(ValueError, match="differs from its digest"):
        corpus_texts(tmp_path)


def test_records_keep_every_byte(tmp_path: Path) -> None:
    """The record format keeps empty, NUL, invalid UTF-8 and oversized inputs exactly."""
    inputs = all_inputs()
    assert len(inputs) == len(set(inputs)) and b"" in inputs and any(len(sql) > 1024 * 1024 for sql in inputs)
    write_records(tmp_path / "inputs", inputs)
    assert read_records(tmp_path / "inputs") == inputs
