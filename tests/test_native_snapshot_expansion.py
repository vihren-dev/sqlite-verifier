"""Validated snapshot transport reconstructs independent observations without changing JSON evidence."""

import hashlib
from copy import deepcopy

import pytest

from conformance import replay_tiers
from conformance.case_format import Json
from conformance.corpus_shards import payload_records
from conformance.execution_profile import ExecutionProfile
from conformance.native_storage import CASE_BYTE_LIMIT, CaseSizeLimit, expanded_record, serialized, shared_record


def repeated_snapshot_record() -> dict[str, Json]:
    """One shared snapshot contains exact typed bytes, integer bounds and nested mutable metadata."""
    snapshot: dict[str, Json] = {"schema": [{"name": "λ\x00", "sql": "schema\ntext"}], "tables": [
        {"name": "t", "columns": [{"name": "v", "notNull": False}], "rows": [{"rowid": 1, "values": [
            {"text": {"bytes": [0, 206, 187]}}, {"blob": {"bytes": [0, 255]}},
            {"integer": {"value": -9223372036854775808}}, {"integer": {"value": 9223372036854775807}},
            {"real": {"bits": "9223372036854775808"}}, "null"]}]}]}
    return {"initial": {"visible": snapshot, "persisted": snapshot}, "trace": [
        {"visible": snapshot, "persisted": snapshot}, {"visible": snapshot, "persisted": snapshot}]}


@pytest.mark.parametrize("bounded", [False, True])
def test_every_occurrence_is_independent_and_exact(bounded: bool) -> None:
    """Mutation of schema, columns, row lists or cell bytes leaves all other occurrences and the pool intact."""
    original = repeated_snapshot_record()
    stored = shared_record(original)
    before = serialized(stored)
    restored = expanded_record(stored, byte_limit=len(serialized(original)) if bounded else None)
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


@pytest.mark.parametrize("damage", ["content", "missing", "reference", "reference-value", "pool-type",
                                  "version", "unused", "unused-corrupt"])
@pytest.mark.parametrize("bounded", [False, True])
def test_pool_and_reference_checks_remain_complete(damage: str, bounded: bool) -> None:
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
    elif damage == "reference-value":
        broken["initial"]["visible"] = {"snapshot": False}
    elif damage == "pool-type":
        broken["snapshots"] = []
    elif damage == "version":
        broken["snapshotStorageVersion"] = True
    else:
        extra: dict[str, Json] = {"schema": [], "tables": []}
        extra_digest = hashlib.sha256(serialized(extra)).hexdigest()
        broken["snapshots"][extra_digest] = extra
        if damage == "unused-corrupt":
            extra["tables"].append({"changed": True})
    with pytest.raises(ValueError, match="snapshot"):
        expanded_record(broken, byte_limit=1 if bounded else None)


def test_historical_unshared_record_retains_existing_primitive() -> None:
    """Historical records bypass shared transport as before, with their original object and bytes."""
    original = repeated_snapshot_record()
    before = serialized(original)
    assert expanded_record(original) is original and serialized(original) == before


@pytest.mark.parametrize("repetitions", [0, 1, 4])
def test_logical_size_matches_independent_serialization(repetitions: int) -> None:
    """Exact canonical limits count every large/empty occurrence and escaped UTF-8 metadata."""
    original = repeated_snapshot_record()
    large = original["initial"]["visible"]
    empty: dict[str, Json] = {"schema": [], "tables": []}
    original["trace"] = [{"visible": large, "persisted": empty}] * repetitions
    original["metadata"] = {"multibyte": "éλ🙂", "escaped": "\x00\n\"\\",
                            "snapshot": {"snapshot": "ordinary metadata"}, "padding": ""}
    stored = shared_record(original, byte_limit=None)
    expected_bytes = serialized(expanded_record(stored))
    limit = len(expected_bytes)
    assert serialized(expanded_record(stored, byte_limit=limit)) == expected_bytes
    with pytest.raises(CaseSizeLimit) as failure:
        expanded_record(stored, byte_limit=limit - 1)
    assert failure.value.byte_count == len(expected_bytes)
    original["metadata"]["padding"] = "a"
    oversized = shared_record(original, byte_limit=None)
    assert len(serialized(expanded_record(oversized))) == limit + 1
    with pytest.raises(CaseSizeLimit) as failure:
        expanded_record(oversized, byte_limit=limit)
    assert failure.value.byte_count == limit + 1


def test_optional_limit_preserves_unshared_primitive_and_exact_size() -> None:
    """The same flexible primitive bounds an unshared record only when requested."""
    original = repeated_snapshot_record()
    limit = len(serialized(original))
    assert expanded_record(original, byte_limit=limit) is original
    with pytest.raises(CaseSizeLimit) as failure:
        expanded_record(original, byte_limit=limit - 1)
    assert failure.value.byte_count == limit


def test_unselected_logical_oversize_still_fails_complete_shard_loading() -> None:
    """A small shared pool cannot conceal an oversized case that selection would omit."""
    # This profile tests transport only; no native-engine observation is claimed.
    profile = ExecutionProfile("size-test", 1, "transport-test", "transport-test", ("TEST",)).to_wire()
    original = repeated_snapshot_record()
    for event in original["trace"]:
        event.update(columns=[], columnCount=0, rows=[], parameters=[], changes=0)
    original.update(nativeVersion=4, sourceId="transport-test", profile=profile,
                    part="upstream", upstream={"file": "size.test"})
    population = replay_tiers.POLICY["additionalUpstream"]
    assert isinstance(population, int)
    records = [{**deepcopy(original), "name": f"candidate-{index}"} for index in range(population + 2)]
    selected = {record["name"] for record in replay_tiers.select(records)}
    omitted = next(record for record in records if record["name"] not in selected)
    snapshot = omitted["initial"]["visible"]
    snapshot["tables"][0]["rows"][0]["values"].append({"blob": {"bytes": [0] * 4096}})
    repetitions = CASE_BYTE_LIMIT // (2 * len(serialized(snapshot))) + 1
    omitted["trace"] = [deepcopy(omitted["trace"][0])] * repetitions
    expected = len(serialized(omitted))
    stored = [shared_record(record, byte_limit=None) for record in records]
    assert expected > CASE_BYTE_LIMIT and all(len(serialized(record)) < CASE_BYTE_LIMIT for record in stored)
    payload = b"".join(serialized(record) + b"\n" for record in stored)
    binding: dict[str, Json] = {"recordedCases": len(records), "casesSha256": hashlib.sha256(payload).hexdigest(),
                               "part": "upstream", "source": "size.test", "executionProfiles": [profile]}
    with pytest.raises(CaseSizeLimit) as failure:
        payload_records(payload, binding)
    assert failure.value.byte_count == expected
