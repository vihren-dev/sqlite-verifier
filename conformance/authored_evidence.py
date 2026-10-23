"""Publish authored coverage cases as a new corpus directory (ADR 0012 slices).

The corpus writers of the query slices share these steps: refuse an existing
directory, replay the recorded cases natively, write them as one shard with ordinary
bindings and the hash of their definitions, read them back, compare, and replay them
again. Claiming a corpus for the judge is a separate, owner-approved change
(ADR 0011).
"""

import argparse
from collections.abc import Callable
from dataclasses import dataclass
import hashlib
import json
from pathlib import Path

from conformance.case_format import Json
from conformance.corpus import load, native_replay
from conformance.corpus_shards import write

NATIVE_VERSION = 5
"""The record version of a corpus that does not give one: each record has measured limits,
error phases and statement outputs."""


@dataclass(frozen=True)
class AuthoredCorpus:
    """One authored corpus: what to record, and how the shard manifest names it."""

    records: Callable[[], list[dict[str, Json]]]
    """Records the cases natively."""
    definitions: Path
    """The module that defines the cases; its hash goes into the manifest."""
    source_name: str
    """The name of the definitions in the shard manifest."""
    part: str
    """The part of each case."""
    corpus_version: int
    """The corpus version of the new directory."""
    evidence_kind: str
    """Distinguishes this evidence from the other corpora."""
    native_version: int = NATIVE_VERSION
    """The record version of each record: 6 for records of the recorder that runs on after an
    error (`record_sql` with `run_on`)."""


def publish(corpus: AuthoredCorpus, directory: Path) -> dict[str, Json]:
    """Acquire, store, load and freshly replay a new corpus directory."""
    if directory.exists() or directory.is_symlink():
        raise ValueError(f"Evidence output already exists: {directory}; choose a new directory")
    acquired = corpus.records()
    native_replay(acquired)
    manifest = write(directory, [(corpus.source_name, corpus.part, acquired)], corpus_version=corpus.corpus_version,
                     native_version=corpus.native_version, metadata={"evidenceKind": corpus.evidence_kind,
                     "definitionsSha256": hashlib.sha256(corpus.definitions.read_bytes()).hexdigest()})
    loaded_manifest, loaded = load(directory)
    if loaded_manifest != manifest or loaded != acquired:
        raise ValueError(f"Evidence differs after storage: {directory}; inspect the corpus bindings")
    native_replay(loaded)
    return manifest


def main(corpus: AuthoredCorpus, description: str) -> None:
    """Create the corpus directory given by `--output` and print its acquisition receipt; the
    description is the help text of the command."""
    parser = argparse.ArgumentParser(description=description)
    parser.add_argument("--output", type=Path, required=True, help="New directory for the corpus")
    manifest = publish(corpus, parser.parse_args().output)
    print(json.dumps({"recordedCases": manifest["recordedCases"], "casesSha256": manifest["casesSha256"],
                      "nativeReplayPassed": True}))
