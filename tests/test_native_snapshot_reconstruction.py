"""Internal snapshot copies retain canonical JSON normalization and independent mutable trees."""

import json
import math

import pytest

from conformance.case_format import Json
from conformance import native_storage
from conformance.native_storage import expanded_record, serialized, shared_record
from tests.test_native_snapshot_expansion import repeated_snapshot_record


class JsonArray(list[Json]):
    """A caller-owned array subclass exposes normalization before internal binary copying."""


class JsonMapping(dict[str, Json]):
    """A caller-owned mapping subclass must become an ordinary JSON object."""


class JsonInteger(int):
    """A JSON-compatible integer subclass must retain its value through normalization."""


@pytest.mark.parametrize("bounded", [False, True])
def test_snapshot_copies_match_independent_json_oracle(bounded: bool) -> None:
    """JSON bytes define exact scalar values and size, including nonfinite floats and signed zero."""
    snapshot: dict[str, Json] = {"schema": [None, False, True, -(2**256), 2**256,
        -0.0, 1e-308, math.inf, -math.inf, math.nan, "λ\x00\n\"\\🙂"], "tables": []}
    original: dict[str, Json] = {"initial": {"visible": snapshot, "persisted": snapshot},
                               "trace": [{"visible": snapshot, "persisted": snapshot}]}
    stored = shared_record(original)
    oracle = json.loads(serialized(original))
    expected = serialized(oracle)
    restored = expanded_record(stored, byte_limit=len(expected) if bounded else None)
    assert serialized(restored) == expected
    assert math.copysign(1, restored["initial"]["visible"]["schema"][5]) == -1
    assert serialized(stored) == serialized(shared_record(original))


@pytest.mark.parametrize("bounded", [False, True])
def test_normalization_erases_nested_aliases_and_subclasses(bounded: bool) -> None:
    """Internal copies preserve JSON's plain types and separate reused caller objects at every depth."""
    reused = JsonArray([JsonMapping(value=JsonArray([JsonInteger(7), True, None]))])
    snapshot: dict[str, Json] = {"schema": [JsonMapping(left=reused, right=reused)], "tables": reused}
    original: dict[str, Json] = {"initial": {"visible": snapshot, "persisted": snapshot}, "trace": []}
    stored = shared_record(original)
    before = serialized(stored)
    oracle = json.loads(serialized(original))
    restored = expanded_record(stored, byte_limit=len(serialized(oracle)) if bounded else None)
    assert restored == oracle
    visible = restored["initial"]["visible"]
    first = visible["schema"][0]["left"]
    assert type(first) is list and type(first[0]) is dict and type(first[0]["value"][0]) is int
    first[0]["value"].append(99)
    assert visible["schema"][0]["right"] == oracle["initial"]["visible"]["schema"][0]["right"]
    assert visible["tables"] == oracle["initial"]["visible"]["tables"]
    assert restored["initial"]["persisted"] == oracle["initial"]["persisted"]
    assert serialized(stored) == before and expanded_record(stored) == oracle


def test_each_pool_snapshot_decodes_json_once(monkeypatch: pytest.MonkeyPatch) -> None:
    """Repeated occurrences reconstruct independently while canonical JSON decoding scales with pool entries."""
    original = repeated_snapshot_record()
    original["initial"]["persisted"] = {"schema": [], "tables": []}
    stored = shared_record(original)
    expected_payloads = [serialized(snapshot) for snapshot in stored["snapshots"].values()]
    decoded: list[bytes] = []
    decode_json = json.loads

    def decode(payload: bytes) -> Json:
        """Observe canonical decoding without replacing its behavior or inspecting private binary bytes."""
        decoded.append(payload)
        return decode_json(payload)

    monkeypatch.setattr(native_storage.json, "loads", decode)
    restored = expanded_record(stored)
    assert restored == original and decoded == expected_payloads
    assert restored["initial"]["visible"] is not restored["trace"][0]["visible"]
