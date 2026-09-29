"""The opt-in stage store restores only verified entries and treats every problem as a miss."""

from pathlib import Path

import pytest

from migration_check.cache_eligibility import approved_reuse_allowed
from migration_check.stage_store import MEASUREMENT_APPROVED_VARIABLE, STORE_VARIABLE, StageStore, stage_key

pytestmark = [pytest.mark.unit, pytest.mark.approval]


def compiled_stage(directory: Path) -> Path:
    """A tiny stand-in for a compiled stage directory."""
    (directory / "Nested").mkdir(parents=True)
    (directory / "Requirements.olean").write_bytes(b"requirements")
    (directory / "Nested/Helper.olean").write_bytes(b"helper")
    return directory


def test_round_trip_restores_identical_read_only_files(tmp_path: Path) -> None:
    """A saved stage restores byte-for-byte into an empty destination."""
    store = StageStore(tmp_path / "store")
    store.save("key", compiled_stage(tmp_path / "compiled"))
    destination = tmp_path / "restored"
    destination.mkdir()
    assert store.restore("key", destination)
    assert (destination / "Nested/Helper.olean").read_bytes() == b"helper"
    assert not (destination / "Requirements.olean").stat().st_mode & 0o222


@pytest.mark.parametrize("damage", ["missing", "changed_file", "removed_file", "bad_manifest"])
def test_damaged_or_missing_entries_are_misses(tmp_path: Path, damage: str) -> None:
    """Missing, altered or unreadable entries are never restored."""
    store = StageStore(tmp_path / "store")
    store.save("key", compiled_stage(tmp_path / "compiled"))
    entry = tmp_path / "store/key"
    if damage == "missing":
        entry = tmp_path / "store/other"
    elif damage == "changed_file":
        (entry / "files/Requirements.olean").chmod(0o644)
        (entry / "files/Requirements.olean").write_bytes(b"tampered")
    elif damage == "removed_file":
        (entry / "files/Nested/Helper.olean").unlink()
    else:
        (entry / "manifest.json").write_text("not json")
    destination = tmp_path / "restored"
    destination.mkdir()
    assert not store.restore(entry.name, destination)


def test_keys_change_with_sources_order_and_runtime() -> None:
    """Any source byte, preceding stage or toolchain/library identity changes the key."""
    base = stage_key("SqlInputs", {"SqlInputs": b"def x := 1"}, ("schema",), ("/lean", "/lib"))
    assert base != stage_key("SqlInputs", {"SqlInputs": b"def x := 2"}, ("schema",), ("/lean", "/lib"))
    assert base != stage_key("SqlInputs", {"SqlInputs": b"def x := 1"}, ("other",), ("/lean", "/lib"))
    assert base != stage_key("SqlInputs", {"SqlInputs": b"def x := 1"}, ("schema",), ("/lean2", "/lib"))


def test_configuration_and_approved_eligibility(monkeypatch: pytest.MonkeyPatch, tmp_path: Path) -> None:
    """No store without configuration; approved closures need review or the measurement override."""
    monkeypatch.delenv(STORE_VARIABLE, raising=False)
    assert StageStore.configured() is None
    monkeypatch.setenv(STORE_VARIABLE, str(tmp_path))
    monkeypatch.delenv(MEASUREMENT_APPROVED_VARIABLE, raising=False)
    store = StageStore.configured()
    assert store is not None and not approved_reuse_allowed("digest", store)
    monkeypatch.setenv(MEASUREMENT_APPROVED_VARIABLE, "1")
    store = StageStore.configured()
    assert store is not None and approved_reuse_allowed("digest", store)
