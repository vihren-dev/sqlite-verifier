"""Validated snapshot transport reconstructs independent observations without changing JSON evidence."""

import hashlib
from copy import deepcopy

import pytest

from conformance.case_format import Json
from conformance.native_storage import expanded_record, serialized, shared_record


def repeated_snapshot_record() -> dict[str, Json]:
    """One shared snapshot contains exact typed bytes, integer bounds and nested mutable metadata."""
    snapshot: dict[str, Json] = {"schema": [{"name": "λ\x00", "sql": "schema\ntext"}], "tables": [
        {"name": "t", "columns": [{"name": "v", "notNull": False}], "rows": [{"rowid": 1, "values": [
            {"text": {"bytes": [0, 206, 187]}}, {"blob": {"bytes": [0, 255]}},
            {"integer": {"value": -9223372036854775808}}, {"integer": {"value": 9223372036854775807}},
            {"real": {"bits": "9223372036854775808"}}, "null"]}]}]}
    return {"initial": {"visible": snapshot, "persisted": snapshot}, "trace": [
        {"visible": snapshot, "persisted": snapshot}, {"visible": snapshot, "persisted": snapshot}]}


def test_every_occurrence_is_independent_and_exact() -> None:
    """Mutation of schema, columns, row lists or cell bytes leaves all other occurrences and the pool intact."""
    original = repeated_snapshot_record()
    stored = shared_record(original)
    before = serialized(stored)
    restored = expanded_record(stored)
    assert restored == original
    observations = [restored["initial"], *restored["trace"]]
    snapshots = [observation[field] for observation in observations for field in ("visible", "persisted")]
    assert len({id(snapshot) for snapshot in snapshots}) == len(snapshots)
    snapshots[0]["schema"][0]["name"] = "changed"
    snapshots[0]["tables"][0]["columns"][0]["notNull"] = True
    snapshots[0]["tables"][0]["rows"][0]["values"][0]["text"]["bytes"].append(255)
    snapshots[0]["tables"][0]["rows"].append({"rowid": 2, "values": []})
    assert all(snapshot == original["initial"]["visible"] for snapshot in snapshots[1:])
    assert serialized(stored) == before and expanded_record(stored) == original


@pytest.mark.parametrize("damage", ["content", "missing", "reference", "unused", "unused-corrupt"])
def test_pool_and_reference_checks_remain_complete(damage: str) -> None:
    """Correct outer transport cannot conceal changed snapshots, invalid references or unused pool entries."""
    stored = shared_record(repeated_snapshot_record())
    broken = deepcopy(stored)
    digest = broken["initial"]["visible"]["snapshot"]
    if damage == "content":
        broken["snapshots"][digest]["tables"][0]["rows"].clear()
    elif damage == "missing":
        broken["snapshots"].pop(digest)
    elif damage == "reference":
        broken["trace"][1]["persisted"] = {"snapshot": digest, "extra": 1}
    else:
        extra: dict[str, Json] = {"schema": [], "tables": []}
        extra_digest = hashlib.sha256(serialized(extra)).hexdigest()
        broken["snapshots"][extra_digest] = extra
        if damage == "unused-corrupt":
            extra["tables"].append({"changed": True})
    with pytest.raises(ValueError, match="snapshot"):
        expanded_record(broken)


def test_historical_unshared_record_retains_existing_primitive() -> None:
    """Historical records bypass shared transport as before, with their original object and bytes."""
    original = repeated_snapshot_record()
    before = serialized(original)
    assert expanded_record(original) is original and serialized(original) == before
