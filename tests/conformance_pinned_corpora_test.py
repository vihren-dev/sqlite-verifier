"""Check `conformance.pinned_corpora` and the pinned path of `conformance.corpus.load`.

`load` decodes a pinned frozen corpus without validating it again. These tests
are the single place where each pinned corpus gets the complete validation by
the current validator. The `frozen` Nix suite runs them again when a corpus or
a validation module changes.
"""

from concurrent.futures import Executor, ProcessPoolExecutor
import gzip
import json
from multiprocessing import get_context
from pathlib import Path
import shutil

import pytest

from conformance import corpus
from conformance.case_format import Json
from conformance.native_storage import serialized
from conformance.native_workers import NATIVE_WORKER_LIMIT
from conformance.corpus import load, validated_load
from conformance.pinned_corpora import PINNED_TREES, is_pinned, tree_digest

ROOT = Path(__file__).resolve().parents[1]
SMALL = "conformance/synthetic-workload/corpus"
pytestmark = [pytest.mark.integration, pytest.mark.conformance]


@pytest.mark.parametrize("digest,label", sorted(PINNED_TREES.items(), key=lambda item: item[1]),
                         ids=sorted(PINNED_TREES.values()))
def test_pinned_corpus_passes_complete_validation(digest: str, label: str) -> None:
    """Each pin is the actual tree, the corpus passes complete validation, and both paths agree.

    Shards are validated in at most four spawned processes, as in
    `conformance.native_workers.load_development_corpus`. A corpus without
    shards has no shared snapshots: both paths then return the parsed lines
    unchanged, so the test does not decode it twice. For a sharded corpus,
    `decoded_record` copies each stored snapshot with its stored key order and
    `expanded_record` copies it in sorted key order. The two orders agree when
    each stored line is canonical JSON, which the test also checks.
    """
    directory = ROOT / label
    assert tree_digest(directory) == digest, f"Pin of {label} differs from its files; validate it and update the pin"
    with ProcessPoolExecutor(max_workers=NATIVE_WORKER_LIMIT, mp_context=get_context("spawn")) as executor:
        manifest, validated = validated_load(directory, executor=executor)
    if "shards" not in manifest:
        assert not any("snapshots" in record for record in validated)
        return
    assert load(directory) == (manifest, validated)
    for shard in manifest["shards"]:
        for line in gzip.decompress((directory / shard["path"]).read_bytes()).splitlines():
            assert serialized(json.loads(line)) == line, f"{label}/{shard['path']} has a non-canonical line"


def test_each_frozen_corpus_directory_is_pinned() -> None:
    """A new frozen corpus version gets a pin, so the pin test validates it."""
    frozen = {path.relative_to(ROOT).as_posix() for path in (ROOT / "conformance").glob("corpus-v*")}
    assert frozen | {SMALL} == set(PINNED_TREES.values())


def copied(tmp_path: Path, label: str) -> Path:
    """Copy one pinned corpus to a private directory that a test can change."""
    return Path(shutil.copytree(ROOT / label, tmp_path / "corpus"))


def refuse_complete_validation(monkeypatch: pytest.MonkeyPatch) -> None:
    """Fail the test when `load` runs the complete validation."""
    def refuse(directory: Path, *, executor: Executor | None = None) -> None:
        """Report the unexpected complete validation."""
        raise AssertionError(f"complete validation of {directory}")

    monkeypatch.setattr(corpus, "validated_load", refuse)


def test_unchanged_copy_uses_the_pinned_path(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    """Pins identify bytes, not paths: an exact copy loads without complete validation."""
    directory = copied(tmp_path, SMALL)
    expected = validated_load(directory)
    refuse_complete_validation(monkeypatch)
    assert load(directory) == expected


def test_changed_shard_gets_complete_validation_and_is_refused(tmp_path: Path) -> None:
    """A changed shard is not pinned, and the complete validation gives its existing error."""
    directory = copied(tmp_path, SMALL)
    shard = next((directory / "shards").iterdir())
    payload = gzip.decompress(shard.read_bytes())
    shard.write_bytes(gzip.compress(payload.replace(b'"name":"', b'"name":"x', 1), mtime=0))
    assert not is_pinned(directory)
    with pytest.raises(ValueError, match="Corpus shard digest mismatch"):
        load(directory)


def test_added_file_gets_complete_validation(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    """An added file changes the tree digest, so `load` runs the complete validation."""
    directory = copied(tmp_path, SMALL)
    (directory / "notes.txt").write_text("unreviewed\n")
    calls: list[Path] = []
    complete = corpus.validated_load

    def observed(path: Path, *, executor: Executor | None = None) -> tuple[dict[str, Json], list[dict[str, Json]]]:
        """Record the complete validation and run it."""
        calls.append(path)
        return complete(path, executor=executor)

    monkeypatch.setattr(corpus, "validated_load", observed)
    load(directory)
    assert calls == [directory]


def test_removed_shard_is_refused(tmp_path: Path) -> None:
    """A removed shard is not pinned, and the complete validation refuses the missing file."""
    directory = copied(tmp_path, SMALL)
    next((directory / "shards").iterdir()).unlink()
    assert not is_pinned(directory)
    with pytest.raises(ValueError, match="Missing source path"):
        load(directory)


@pytest.mark.parametrize("relative", ["extraction.json.gz", "fidelity"])
def test_changed_evidence_file_is_not_pinned(tmp_path: Path, relative: str) -> None:
    """Extraction and fidelity files are part of the tree digest, as are shards."""
    directory = copied(tmp_path, "conformance/corpus-v5")
    path = directory / relative
    if path.is_dir():
        path = sorted(item for item in path.rglob("*") if item.is_file())[0]
    path.write_bytes(path.read_bytes() + b"\n")
    assert is_pinned(ROOT / "conformance/corpus-v5")
    assert not is_pinned(directory)


def test_symbolic_link_is_never_pinned(tmp_path: Path) -> None:
    """A link could point outside the reviewed bytes, so a tree with a link has no digest."""
    directory = copied(tmp_path, SMALL)
    shard = next((directory / "shards").iterdir())
    target = tmp_path / "outside.gz"
    shard.rename(target)
    shard.symlink_to(target)
    assert tree_digest(directory) is None
    assert not is_pinned(directory)
