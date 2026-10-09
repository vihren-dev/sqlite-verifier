"""Write the inputs of the parser library checks: parser test inputs and corpus SQL texts.

The checks parse every parser test input and every distinct SQL text of every retained
corpus with each grammar of the library. This module reads the corpus files directly,
without the conformance harness, so that a change of the harness code does not rerun
the checks. The output is a sequence of records: a 4-byte little-endian length, then the
SQL bytes.
"""

import argparse
import gzip
import hashlib
import json
from pathlib import Path
import struct

from tests.parser_inputs import all_inputs

SQL_FIELDS = ("migrationSql", "setupSql")
"""The case fields that hold one SQL text each."""


def payloads(corpus: Path) -> list[bytes]:
    """Return the decompressed case files of a corpus, checked against their manifest digests."""
    manifest = json.loads((corpus / "manifest.json").read_text())
    if "shards" in manifest:
        bindings = [(corpus / shard["path"], shard["casesSha256"]) for shard in manifest["shards"]]
    else:
        bindings = [(corpus / "cases.jsonl.gz", manifest["casesSha256"])]
    result = []
    for path, digest in bindings:
        payload = gzip.decompress(path.read_bytes())
        if hashlib.sha256(payload).hexdigest() != digest:
            raise ValueError(f"{path} differs from its digest in {corpus / 'manifest.json'}")
        result.append(payload)
    return result


def case_texts(case: dict[str, object]) -> list[str]:
    """Return the migration, setup, setup command and traced statement texts of a case."""
    texts = [case[field] for field in SQL_FIELDS]
    commands = case.get("setupCommands", [])
    trace = case.get("trace", [])
    if not isinstance(commands, list) or not isinstance(trace, list):
        raise ValueError(f"Case {case.get('name')!r} has an invalid setup command list or trace")
    texts += commands + [event.get("sql") for event in trace if isinstance(event, dict)]
    return [text for text in texts if isinstance(text, str)]


def corpus_texts(corpus: Path) -> set[str]:
    """Return the distinct SQL texts of all cases of a corpus."""
    texts: set[str] = set()
    for payload in payloads(corpus):
        for line in payload.splitlines():
            texts.update(case_texts(json.loads(line)))
    return texts


def write_records(path: Path, inputs: list[bytes]) -> None:
    """Write length-prefixed records."""
    with path.open("wb") as stream:
        for sql in inputs:
            stream.write(struct.pack("<I", len(sql)) + sql)


def read_records(path: Path) -> list[bytes]:
    """Read the records that write_records wrote."""
    data = path.read_bytes()
    records, offset = [], 0
    while offset < len(data):
        (size,) = struct.unpack_from("<I", data, offset)
        records.append(data[offset + 4:offset + 4 + size])
        offset += 4 + size
    return records


def main() -> None:
    """Write the parser test inputs, then the sorted corpus texts that are not among them."""
    cli = argparse.ArgumentParser(description=__doc__)
    cli.add_argument("--corpus", type=Path, action="append", required=True)
    cli.add_argument("--output", type=Path, required=True)
    arguments = cli.parse_args()
    texts = set().union(*(corpus_texts(corpus) for corpus in arguments.corpus))
    tests = all_inputs()
    write_records(arguments.output, tests + sorted({text.encode() for text in texts} - set(tests)))


if __name__ == "__main__":
    main()
