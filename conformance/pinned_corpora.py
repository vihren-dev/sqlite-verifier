"""Load frozen corpora whose complete bytes the repository pins after one complete validation.

`conformance.corpus.validated_load` checks a corpus completely: digests,
counts, formats, snapshots, profiles, and acquisition and fidelity evidence.
A frozen corpus does not change, so that result does not change for the same
bytes and the same validator. `tests/conformance_pinned_corpora_test.py`, in
the `pinned` Nix suite, runs the complete validation on each pinned corpus.
That suite's inputs are only the pinned corpora and the modules that the
validation imports, so it runs again only when one of them changes.

`conformance.corpus.load` uses `pinned_records` when the tree digest of a
directory is in `PINNED_TREES`. Any changed, added or removed file gives a
different digest, and that corpus gets the complete validation.
"""

import gzip
import hashlib
import json
from pathlib import Path

from conformance.case_format import Json
from conformance.native_storage import decoded_record

PINNED_TREES: dict[str, str] = json.loads(Path(__file__).with_name("pinned-corpora.json").read_text())
"""Tree digest of each frozen corpus that passed complete validation, and its directory.

The pins are in `pinned-corpora.json`, so that the `pinned` Nix suite
(`build-support/tests.nix`) can use the same directories as its inputs. To
freeze or change a corpus, run the complete validation and put the new
`tree_digest` there. The pin test fails until the digest and the bytes agree.
"""


def tree_digest(directory: Path) -> str | None:
    """Give one SHA-256 digest of each regular file's relative path and content digest.

    The result is `None` when the tree has a symbolic link or another
    non-regular entry: such a tree is never pinned.
    """
    entries: list[list[str]] = []
    for path in sorted(directory.rglob("*")):
        if path.is_symlink() or not (path.is_dir() or path.is_file()):
            return None
        if path.is_file():
            entries.append([path.relative_to(directory).as_posix(), hashlib.sha256(path.read_bytes()).hexdigest()])
    return hashlib.sha256(json.dumps(entries, separators=(",", ":")).encode()).hexdigest()


def is_pinned(directory: Path) -> bool:
    """Tell whether the directory has exactly the bytes of a validated frozen corpus."""
    return directory.is_dir() and not directory.is_symlink() and tree_digest(directory) in PINNED_TREES


def pinned_records(directory: Path, manifest: dict[str, Json]) -> list[dict[str, Json]]:
    """Decode the cases of a pinned corpus, in manifest order, without validating them again.

    Use this only after `is_pinned` is true for the same unchanged directory.
    """
    paths = [shard["path"] for shard in manifest["shards"]] if "shards" in manifest else ["cases.jsonl.gz"]
    return [decoded_record(json.loads(line))
            for relative in paths
            for line in gzip.decompress((directory / relative).read_bytes()).splitlines()]
