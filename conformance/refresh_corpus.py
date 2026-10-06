"""Append newly captured upstream and authored cases to an immutable corpus version."""

import argparse
import gzip
import hashlib
import json
from pathlib import Path

from conformance.case_format import Json
from conformance.corpus import load
from conformance.requirement_cases import records as authored_records
from conformance.native_storage import shared_record, serialized
from conformance.execution_profile import validate_manifest_profiles


def refresh(base: Path, upstream: Path, inventory: Path, output: Path) -> dict[str, Json]:
    """Preserve parent observations through shared storage; keep stale citations as provenance."""
    parent, records = load(base)
    capture, candidates = load(upstream)
    candidates += authored_records()
    requirements = json.loads(inventory.read_text())["requirements"]
    names = {record["name"] for record in records}
    additions: list[dict[str, Json]] = []
    for record in candidates:
        if record["name"] in names:
            continue
        tags, unmapped = [], []
        for tag in record["requirements"]:
            matches = [row for row in requirements if row["id"].startswith(tag)]
            (tags if len(matches) == 1 else unmapped).append(tag)
        if unmapped and "upstream" not in record:
            raise ValueError(f"Invalid authored requirement tags: {unmapped}")
        record["requirements"] = tags
        if unmapped:
            record["upstream"]["unmappedEvidenceReferences"] = unmapped
        names.add(record["name"])
        additions.append(record)
    payload = b"".join(serialized(shared_record(record, byte_limit=None)) + b"\n" for record in records)
    payload += b"".join(serialized(shared_record(record)) + b"\n" for record in additions)
    profiles: list[Json] = []
    for profile in parent.get("executionProfiles", []) + capture.get("executionProfiles", []):
        if profile not in profiles:
            profiles.append(profile)
    validate_manifest_profiles({"executionProfiles": profiles}, records + additions)
    manifest = {"corpusVersion": parent["corpusVersion"] + 1, "recordedCases": len(records) + len(additions),
        "casesSha256": hashlib.sha256(payload).hexdigest(), "parentVersion": parent["corpusVersion"],
        "parentCasesSha256": parent["casesSha256"], "upstreamCaptureSha256": capture["casesSha256"],
        "upstreamManifestSha256": hashlib.sha256((upstream / "manifest.json").read_bytes()).hexdigest(),
        "requirementsSha256": hashlib.sha256(inventory.read_bytes()).hexdigest(),
        "addedUpstreamCases": sum("upstream" in record for record in additions),
        "addedAuthoredCases": sum("upstream" not in record for record in additions),
        "sourceSha256": {name: hashlib.sha256(Path(__file__).with_name(name).read_bytes()).hexdigest()
                         for name in ("refresh_corpus.py", "requirement_cases.py", "native_storage.py")},
        **({"executionProfiles": profiles} if profiles else {})}
    output.mkdir()  # Existing evidence must never be overwritten.
    (output / "cases.jsonl.gz").write_bytes(gzip.compress(payload, mtime=0))
    (output / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    return manifest


def main() -> None:
    """Make the parent corpus, native capture and requirement inventory explicit inputs."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base", type=Path, default=Path("conformance/corpus-v2"))
    parser.add_argument("--upstream", type=Path, required=True)
    parser.add_argument("--requirements", type=Path, default=Path("conformance/requirements-3.51.0.json"))
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    print(json.dumps(refresh(args.base, args.upstream, args.requirements, args.output)))


if __name__ == "__main__":
    main()
