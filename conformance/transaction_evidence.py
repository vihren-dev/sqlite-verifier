"""Publish separately named, replayed immediate-transaction evidence with ordinary corpus bindings."""

import argparse
import hashlib
import json
from pathlib import Path

from conformance.authored_cases import records
from conformance.authored_transactions import definitions
from conformance.case_format import Json
from conformance.corpus import load, native_replay
from conformance.corpus_shards import write

SOURCE_NAME = "authored-immediate-transactions"
"""Identify the authored transaction definitions in the shard manifest."""
PART_NAME = "boundary-interaction"
"""Group these cases by interactions between transaction boundaries."""
CORPUS_VERSION = 1
"""Mark the first version of this new corpus; its directory and kind separate it from frozen corpora."""
EVIDENCE_KIND = "grouped-immediate-transactions"
"""Distinguish this evidence from the historical conformance corpora."""


def publish(directory: Path) -> dict[str, Json]:
    """Acquire, store, load and freshly replay a new evidence directory without replacing old files."""
    if directory.exists() or directory.is_symlink():
        raise ValueError(f"Transaction evidence output already exists: {directory}; choose a new directory")
    acquired = records(definitions())
    native_replay(acquired)
    source = Path(__file__).with_name("authored_transactions.py")
    manifest = write(directory, [(SOURCE_NAME, PART_NAME, acquired)],
        corpus_version=CORPUS_VERSION, metadata={"evidenceKind": EVIDENCE_KIND,
            "definitionsSha256": hashlib.sha256(source.read_bytes()).hexdigest()})
    loaded_manifest, loaded = load(directory)
    if loaded_manifest != manifest or loaded != acquired:
        raise ValueError(f"Transaction evidence differs after storage: {directory}; inspect the corpus bindings")
    native_replay(loaded)
    return manifest


def main() -> None:
    """Create a digest-bound evidence directory and print its checked acquisition receipt."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True, help="New directory for the separately named evidence")
    args = parser.parse_args()
    manifest = publish(args.output)
    print(json.dumps({"recordedCases": manifest["recordedCases"], "casesSha256": manifest["casesSha256"],
                      "nativeReplayPassed": True}))


if __name__ == "__main__":
    main()
