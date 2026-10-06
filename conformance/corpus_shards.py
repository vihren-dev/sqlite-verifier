"""Versioned per-source transport binds new profiled evidence without changing old corpora."""

import gzip
import hashlib
import json
from pathlib import Path

from conformance.case_format import Json
from conformance.execution_profile import validate_manifest_profiles
from conformance.native_replay import output_wire
from conformance.native_call_recording import validate_recording
from conformance.native_storage import check_size, expanded_record, serialized, shared_record

FORMATS = {"shardStorageVersion": 1, "caseFormatVersion": 2,
           "nativeVersion": 4, "snapshotStorageVersion": 1}


def source_path(directory: Path, relative: Json) -> Path:
    """Read only canonical relative files, including when symlinks try to escape the root."""
    if (not isinstance(relative, str) or not relative or "\\" in relative
            or Path(relative).is_absolute() or any(part in {"", ".", ".."} for part in relative.split("/"))):
        raise ValueError("Invalid relative source path")
    try:
        path = (directory / relative).resolve(strict=True)
    except OSError as error:
        raise ValueError("Missing source path") from error
    if not path.is_relative_to(directory.resolve()) or not path.is_file():
        raise ValueError("Source path escapes directory or is not a file")
    return path


def natural(value: Json, *, positive: bool = False) -> int:
    """Counts and corpus identities exclude booleans and negative values."""
    if type(value) is not int or value < int(positive):
        raise ValueError("Invalid corpus version or count")
    return value


def formats(value: dict[str, Json], *, root: bool = False) -> None:
    """Corpus, native acquisition, model case and snapshot storage versions are independent."""
    for field, expected in FORMATS.items():
        if field == "shardStorageVersion" and not root:
            continue
        if type(value.get(field)) is not int or value[field] != expected:
            raise ValueError(f"Unsupported corpus format: {field}")


def profiles(records: list[dict[str, Json]]) -> list[Json]:
    """Retain each complete profile in encounter order, without normalizing native truth."""
    unique = {serialized(record.get("profile")): record.get("profile") for record in records}
    return list(unique.values())


def validate_profiles(binding: dict[str, Json], records: list[dict[str, Json]]) -> None:
    """Declarations must match exactly the profiles used by the bound records."""
    try:
        validate_manifest_profiles(binding, records)
        if {serialized(profile) for profile in binding["executionProfiles"]} != {
                serialized(profile) for profile in profiles(records)}:
            raise ValueError("Corpus execution profile declarations differ")
    except (KeyError, TypeError) as error:
        raise ValueError("Invalid corpus execution profiles") from error


def payload_records(payload: bytes, binding: dict[str, Json]) -> list[dict[str, Json]]:
    """Verify transport and every final logical case before accepting a shard denominator."""
    if hashlib.sha256(payload).hexdigest() != binding.get("casesSha256"):
        raise ValueError("Corpus shard digest mismatch")
    count = natural(binding.get("recordedCases"), positive=True)
    stored = [json.loads(line) for line in payload.splitlines()]
    if len(stored) != count:
        raise ValueError("Corpus shard count mismatch")
    result: list[dict[str, Json]] = []
    for value in stored:
        if not isinstance(value, dict):
            raise ValueError("Invalid corpus shard record")
        for field in ("nativeVersion", "snapshotStorageVersion"):
            if type(value.get(field)) is not int or value[field] != FORMATS[field]:
                raise ValueError(f"Unsupported corpus record format: {field}")
        check_size(len(serialized(value)))
        record = expanded_record(value)
        try:
            validate_recording(record)
        except (KeyError, TypeError, IndexError) as error:
            raise ValueError(f"Invalid corpus binding recording: {error}") from error
        check_size(len(serialized(record)))
        if not isinstance(record.get("name"), str) or not record["name"]:
            raise ValueError("Invalid corpus case name")
        upstream = record.get("upstream")
        if (record.get("part") != binding.get("part") or binding.get("part") == "upstream" and (
                not isinstance(upstream, dict) or upstream.get("file") != binding.get("source"))):
            raise ValueError("Corpus shard part or source differs from case evidence")
        for event in record["trace"]:
            try:
                output_wire(event)
            except (KeyError, TypeError) as error:
                raise ValueError("Invalid corpus native output") from error
        result.append(record)
    validate_profiles(binding, result)
    return result


def load(directory: Path, manifest: dict[str, Json]) -> list[dict[str, Json]]:
    """Verify ordered shards, exact profiles and the combined payload before model replay."""
    formats(manifest, root=True)
    natural(manifest.get("corpusVersion"), positive=True)
    count = natural(manifest.get("recordedCases"))
    shards = manifest.get("shards")
    if not isinstance(shards, list) or not shards:
        raise ValueError("Invalid corpus shards")
    paths: set[Path] = set()
    identities: set[tuple[str, str]] = set()
    names: set[str] = set()
    records: list[dict[str, Json]] = []
    combined = hashlib.sha256()
    for shard in shards:
        if not isinstance(shard, dict):
            raise ValueError("Invalid corpus shard declaration")
        formats(shard)
        identity = (shard.get("source"), shard.get("part"))
        if any(not isinstance(item, str) or not item.strip() for item in identity) or identity in identities:
            raise ValueError("Invalid or duplicate corpus shard identity")
        identities.add(identity)
        path = source_path(directory, shard.get("path"))
        if path in paths:
            raise ValueError("Duplicate corpus shard path")
        paths.add(path)
        payload = gzip.decompress(path.read_bytes())
        loaded = payload_records(payload, shard)
        for record in loaded:
            if record["name"] in names:
                raise ValueError("Duplicate corpus case name")
            names.add(record["name"])
        records.extend(loaded)
        combined.update(payload)
    if len(records) != count or combined.hexdigest() != manifest.get("casesSha256"):
        raise ValueError("Combined corpus count or digest mismatch")
    validate_profiles(manifest, records)
    if {"extraction", "fidelityLedger"} & manifest.keys():
        from conformance.corpus_evidence import verify
        verify(directory, manifest, records)
    return records


def write(directory: Path, shards: list[tuple[str, str, list[dict[str, Json]]]], *,
          corpus_version: int = 4, metadata: dict[str, Json] | None = None) -> dict[str, Json]:
    """Validate all inputs before freezing a new directory; existing evidence is never replaced."""
    if directory.exists() or directory.is_symlink():
        raise ValueError("Corpus output already exists")
    natural(corpus_version, positive=True)
    if not shards:
        raise ValueError("Invalid corpus shards")
    declarations: list[Json] = []
    compressed: list[tuple[str, bytes]] = []
    records: list[dict[str, Json]] = []
    identities: set[tuple[str, str]] = set()
    names: set[str] = set()
    combined = hashlib.sha256()
    for index, (source, part, cases) in enumerate(shards):
        identity = (source, part)
        if any(not isinstance(item, str) or not item.strip() for item in identity) or identity in identities:
            raise ValueError("Invalid or duplicate corpus shard identity")
        identities.add(identity)
        path = f"shards/{index:04d}.jsonl.gz"
        payload = b"".join(serialized(shared_record(case)) + b"\n" for case in cases)
        declaration: dict[str, Json] = {"path": path, "source": source, "part": part,
            "recordedCases": len(cases), "casesSha256": hashlib.sha256(payload).hexdigest(),
            "executionProfiles": profiles(cases),
            **{field: version for field, version in FORMATS.items() if field != "shardStorageVersion"}}
        checked = payload_records(payload, declaration)
        for record in checked:
            if record["name"] in names:
                raise ValueError("Duplicate corpus case name")
            names.add(record["name"])
        records.extend(checked)
        declarations.append(declaration)
        compressed.append((path, gzip.compress(payload, mtime=0)))
        combined.update(payload)
    manifest: dict[str, Json] = {**FORMATS, "corpusVersion": corpus_version,
        "recordedCases": len(records), "casesSha256": combined.hexdigest(),
        "executionProfiles": profiles(records), "shards": declarations}
    if metadata is not None and manifest.keys() & metadata.keys():
        raise ValueError("Corpus metadata overrides binding fields")
    manifest.update(metadata or {})
    validate_profiles(manifest, records)
    manifest_bytes = serialized(manifest) + b"\n"
    directory.mkdir(parents=True)
    (directory / "shards").mkdir()
    for relative, payload in compressed:
        (directory / relative).write_bytes(payload)
    (directory / "manifest.json").write_bytes(manifest_bytes)
    return manifest
