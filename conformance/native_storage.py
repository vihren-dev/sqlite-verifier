"""Bound new native cases and share snapshots without changing their observations."""

import hashlib
import json

from conformance.case_format import Json

CASE_BYTE_LIMIT = 1_000_000


class CaseSizeLimit(ValueError):
    """Retain measured exclusion size separately from the human-readable reason."""

    def __init__(self, byte_count: int, limit: int) -> None:
        self.byte_count = byte_count
        super().__init__(f"case size limit: {byte_count} bytes exceeds {limit} bytes")


def serialized(value: Json) -> bytes:
    """Use deterministic UTF-8 JSON for storage digests and size measurements."""
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode()


def check_size(byte_count: int, limit: int = CASE_BYTE_LIMIT) -> None:
    """Accept the exact limit and report an oversized logical case before sharing."""
    if type(byte_count) is not int or byte_count < 0 or type(limit) is not int or limit < 1:
        raise ValueError("Invalid native case byte count or limit")
    if byte_count > limit:
        raise CaseSizeLimit(byte_count, limit)


def observations(record: dict[str, Json]) -> list[dict[str, Json]]:
    """Validate the storage boundary while leaving SQL evidence validation to replay."""
    initial, trace = record.get("initial"), record.get("trace")
    if not isinstance(initial, dict) or not isinstance(trace, list) or any(not isinstance(event, dict) for event in trace):
        raise ValueError("Invalid native storage observations")
    return [initial, *trace]


def shared_record(record: dict[str, Json], *, byte_limit: int | None = CASE_BYTE_LIMIT) -> dict[str, Json]:
    """Share complete snapshots after checking the final expanded evidence size."""
    if "snapshotStorageVersion" in record or "snapshots" in record:
        raise ValueError("Native case is already in shared storage")
    if byte_limit is not None:
        check_size(len(serialized(record)), byte_limit)
    snapshots: dict[str, Json] = {}
    stored: list[dict[str, Json]] = []
    for observation in observations(record):
        copied = dict(observation)
        for field in ("visible", "persisted"):
            snapshot = copied.get(field)
            if not isinstance(snapshot, dict) or set(snapshot) != {"schema", "tables"}:
                raise ValueError("Invalid native snapshot")
            digest = hashlib.sha256(serialized(snapshot)).hexdigest()
            snapshots[digest] = snapshot
            copied[field] = {"snapshot": digest}
        stored.append(copied)
    result = {**record, "snapshotStorageVersion": 1, "snapshots": snapshots,
              "initial": stored[0], "trace": stored[1:]}
    if byte_limit is not None:
        check_size(len(serialized(result)), byte_limit)
    return result


def expanded_record(value: Json) -> dict[str, Json]:
    """Verify every digest/reference, then reconstruct independent observations from each validated JSON payload."""
    if not isinstance(value, dict):
        raise ValueError("Invalid native record")
    if "snapshotStorageVersion" not in value and "snapshots" not in value:
        return value  # Frozen legacy cases keep their observations and size policy.
    if type(value.get("snapshotStorageVersion")) is not int or value["snapshotStorageVersion"] != 1:
        raise ValueError("Unsupported native snapshot storage version")
    snapshots = value.get("snapshots")
    if not isinstance(snapshots, dict):
        raise ValueError("Invalid native snapshot pool")
    validated_snapshot_json: dict[str, bytes] = {}
    for digest, snapshot in snapshots.items():
        if not isinstance(snapshot, dict) or set(snapshot) != {"schema", "tables"}:
            raise ValueError("Native snapshot digest or content differs")
        payload = serialized(snapshot)
        if hashlib.sha256(payload).hexdigest() != digest:
            raise ValueError("Native snapshot digest or content differs")
        validated_snapshot_json[digest] = payload
    used: set[str] = set()
    restored: list[dict[str, Json]] = []
    for observation in observations(value):
        copied = dict(observation)
        for field in ("visible", "persisted"):
            reference = copied.get(field)
            if not isinstance(reference, dict) or set(reference) != {"snapshot"}:
                raise ValueError("Invalid native snapshot reference")
            digest = reference["snapshot"]
            if not isinstance(digest, str) or digest not in snapshots:
                raise ValueError("Missing native snapshot reference")
            copied[field] = json.loads(validated_snapshot_json[digest])
            used.add(digest)
        restored.append(copied)
    if used != set(snapshots):
        raise ValueError("Native snapshot pool contains unused evidence")
    result = {key: item for key, item in value.items() if key not in {"snapshotStorageVersion", "snapshots"}}
    return {**result, "initial": restored[0], "trace": restored[1:]}
