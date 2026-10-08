"""Exact reference-size shortcuts preserve independent JSON limits and subtype behavior."""

from collections.abc import ItemsView, Iterator
import hashlib
import json

import pytest

from conformance import native_storage
from conformance.case_format import Json
from conformance.native_storage import CaseSizeLimit, expanded_record, shared_record


class JsonText(str):
    """A caller-owned string subtype must retain the existing JSON size path."""


class JsonReference(dict[str, Json]):
    """A reference subtype can have JSON output beyond its visible dictionary shape."""

    def items(self) -> ItemsView[str, Json]:
        """Expose escaped Unicode metadata only to the JSON encoder, as the prior path permits."""
        return {**dict(super().items()), "annotation": "λ\x00\n\\\""}.items()


class IterationSensitiveReference(dict[str, Json]):
    """A generic subtype can encode through items without permitting a new iteration."""

    def __iter__(self) -> Iterator[str]:
        """Reject shortcut inspection that the existing serializer does not require."""
        raise AssertionError("The reference subtype must use its existing encoder path")


def oracle(value: Json) -> bytes:
    """Use the standard JSON encoder directly, independent of size and storage helpers."""
    return json.dumps(value, sort_keys=True, ensure_ascii=False, separators=(",", ":")).encode()


@pytest.mark.parametrize("reference", [
    {"snapshot": hashlib.sha256(b"").hexdigest()}, {"snapshot": "ASCII123"},
    {"snapshot": ""}, {"snapshot": "quoted\"\\\x00\n"}, {"snapshot": "λ🙂"},
    {"snapshot": None}, {"other": "ASCII123"}, {"snapshot": "ASCII123", "extra": 1},
    {JsonText("snapshot"): "ASCII123"}, {"snapshot": JsonText("ASCII123")},
    JsonReference(snapshot="ASCII123"),
    IterationSensitiveReference(snapshot="ASCII123"),
])
def test_reference_count_matches_independent_canonical_json(reference: dict[str, Json]) -> None:
    """All shapes and escaped/multibyte/subtype values keep exact canonical byte lengths."""
    assert native_storage._reference_byte_count(reference, reference.get("snapshot")) == len(oracle(reference))


@pytest.mark.parametrize("variant", ["plain", "key-subtype", "digest-subtype", "mapping-subtype"])
def test_exact_limit_and_one_byte_refusal_with_reference_subtypes(variant: str) -> None:
    """Independent expanded JSON sizes include negative empty-snapshot deltas and subtype-only rendering."""
    empty: dict[str, Json] = {"schema": [], "tables": []}
    original: dict[str, Json] = {"metadata": "λ\x00\n\\\"", "initial": {"visible": empty, "persisted": empty},
        "trace": [{"visible": empty, "persisted": empty}, {"visible": empty, "persisted": empty}]}
    stored = shared_record(original, byte_limit=None)
    digest = next(iter(stored["snapshots"]))
    observations = [stored["initial"], *stored["trace"]]
    for observation in observations:
        for field in ("visible", "persisted"):
            if variant == "key-subtype":
                observation[field] = {JsonText("snapshot"): digest}
            elif variant == "digest-subtype":
                observation[field] = {"snapshot": JsonText(digest)}
            elif variant == "mapping-subtype":
                observation[field] = JsonReference(snapshot=digest)
    before = oracle(stored)
    expected = oracle(original)
    assert oracle(expanded_record(stored)) == expected
    assert oracle(expanded_record(stored, byte_limit=len(expected))) == expected
    with pytest.raises(CaseSizeLimit) as failure:
        expanded_record(stored, byte_limit=len(expected) - 1)
    assert failure.value.byte_count == len(expected)
    assert oracle(stored) == before


@pytest.mark.parametrize("variant", ["plain", "key-subtype", "digest-subtype", "mapping-subtype"])
def test_validated_references_use_only_the_proven_shortcut(variant: str, monkeypatch: pytest.MonkeyPatch) -> None:
    """Normal SHA references avoid encoding; subtypes retain the existing serializer after validation."""
    empty: dict[str, Json] = {"schema": [], "tables": []}
    original: dict[str, Json] = {"initial": {"visible": empty, "persisted": empty}, "trace": []}
    stored = shared_record(original, byte_limit=None)
    digest = next(iter(stored["snapshots"]))
    references: list[Json] = []
    for field in ("visible", "persisted"):
        reference: dict[str, Json] = {"snapshot": digest}
        if variant == "key-subtype":
            reference = {JsonText("snapshot"): digest}
        elif variant == "digest-subtype":
            reference = {"snapshot": JsonText(digest)}
        elif variant == "mapping-subtype":
            reference = JsonReference(snapshot=digest)
        stored["initial"][field] = reference
        references.append(reference)
    encoded: list[Json] = []
    encode = native_storage.serialized

    def observed(value: Json) -> bytes:
        """Observe actual reference encodings while keeping the standard encoder's behavior."""
        if any(value is reference for reference in references):
            encoded.append(value)
        return encode(value)

    monkeypatch.setattr(native_storage, "serialized", observed)
    assert oracle(expanded_record(stored, byte_limit=len(oracle(original)))) == oracle(original)
    assert encoded == ([] if variant == "plain" else references)
