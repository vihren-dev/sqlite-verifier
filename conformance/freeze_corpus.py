"""Freeze repaired generic v5 membership only after evidence, replay and budget checks."""

import argparse
from collections import Counter
import gzip
import json
from pathlib import Path
import shutil
from tempfile import TemporaryDirectory

from conformance.authored_boundaries import definitions as boundary_definitions
from conformance.authored_cases import records as authored_records
from conformance.authored_review import definitions as review_definitions
from conformance.case_format import Json
from conformance.corpus import load, native_replay
from conformance.corpus_evidence import feature_counts
from conformance.corpus_shards import natural, source_path, write
from conformance.freeze_validation import acquisition, digest, triage
from conformance.native_storage import check_size, serialized
from conformance.requirement_coverage import credited_upstream, resolved_ids
from conformance.upstream_catalog import catalog_patterns

ROOT = Path(__file__).resolve().parents[1]
CURRENT_BYTE_LIMIT = 25_000_000
RETAINED_BYTE_LIMIT = 60_000_000


def code_hashes() -> dict[str, Json]:
    """Bind the complete current conformance implementation and pinned native build inputs."""
    paths = [*sorted((ROOT / "conformance").glob("*.py")), *sorted((ROOT / "conformance").glob("upstream*.tcl")),
             ROOT / "nix/sqlite.nix", ROOT / "nix/flake.lock", ROOT / "build-support/conformance-native.nix"]
    return {str(path.relative_to(ROOT)): digest(path.read_bytes()) for path in paths}


def retained_bytes(directories: tuple[Path, ...]) -> list[dict[str, Json]]:
    """Measure every actual retained artifact without loading historical oversized cases."""
    result: list[dict[str, Json]] = []
    seen: set[int] = set()
    for directory in directories:
        manifest_path = source_path(directory, "manifest.json")
        manifest = json.loads(manifest_path.read_bytes())
        version = natural(manifest.get("corpusVersion"), positive=True)
        if version not in {1, 2, 3, 4} or version in seen:
            raise ValueError("Invalid or duplicate retained corpus version")
        seen.add(version)
        size = sum(path.stat().st_size for path in directory.rglob("*") if path.is_file())
        result.append({"corpusVersion": version, "directory": directory.name, "bytes": size,
                       "manifestSha256": digest(manifest_path.read_bytes())})
    if seen != {1, 2, 3, 4}:
        raise ValueError("Retained corpus versions 1, 2, 3 and 4 must all be accounted for")
    return result


def membership(upstream: list[dict[str, Json]]) -> list[tuple[str, str, list[dict[str, Json]]]]:
    """Use fresh authored catalogs and recorded upstream sources, never inherited legacy outputs."""
    authored = authored_records()
    boundaries = [{**record, "part": "issue-boundary"}
                  for record in authored_records(boundary_definitions())]
    shards: list[tuple[str, str, list[dict[str, Json]]]] = []
    for part in ("boundary-interaction", "requirement"):
        selected = [record for record in authored if record["part"] == part]
        if selected:
            shards.append(("authored", part, selected))
    if len(authored) != sum(len(cases) for _source, _part, cases in shards):
        raise ValueError("Unknown authored membership part")
    if boundaries:
        shards.append(("issue-boundaries", "issue-boundary", boundaries))
    review = authored_records(review_definitions())
    if review:
        shards.append(("review-boundaries", "boundary-interaction", review))
    for filename in catalog_patterns():
        selected = [record for record in upstream if record["upstream"]["file"] == filename]
        if selected:
            shards.append((filename, "upstream", selected))
    return shards


def freeze(directory: Path, output: Path, *, upstream: Path, fidelity_ledger: Path | None = None,
           retained: tuple[Path, ...] | None = None, temporary_root: Path | None = None,
           storage_report: Path | None = None) -> dict[str, Json]:
    """Publish a new v5 directory only after all selection and native evidence gates pass."""
    if output.exists() or output.is_symlink():
        raise ValueError("Corpus output already exists")
    if storage_report is not None:
        from conformance.native_replay_report import check_receipt_path
        check_receipt_path(storage_report, temporary_root, directory, output)
    extraction = source_path(directory, "manifest.json").read_bytes()
    report, captured = load(directory)
    refusals = acquisition(report, captured, upstream, ROOT)
    ledger_bytes = fidelity_ledger.read_bytes() if fidelity_ledger is not None else None
    ledger = json.loads(ledger_bytes) if ledger_bytes is not None else None
    evidence = triage(ledger, refusals, digest(extraction),
                      fidelity_ledger.parent if fidelity_ledger is not None else directory)
    if "fidelity-ledger.json.gz" in evidence:
        raise ValueError("Fidelity evidence overrides retained ledger")
    inventory_path = ROOT / "conformance/requirements-3.51.0.json"
    inventory = json.loads(inventory_path.read_bytes())
    shards = membership(credited_upstream(captured, inventory))
    cases = [case for _source, _part, selected in shards for case in selected]
    resolved_ids(cases, inventory)
    if any(type(case.get("nativeVersion")) is not int or case["nativeVersion"] != 4 for case in cases):
        raise ValueError("Final membership requires native v4 outputs and profiles")
    for case in cases:
        check_size(len(serialized(case)))
    if temporary_root is None:
        native_replay(cases)
    else:
        from conformance.native_replay_report import report as native_report
        native = native_report(directory, cases, None, temporary_root)
        if storage_report is not None:
            storage_report.parent.mkdir(parents=True, exist_ok=True)
            with storage_report.open('x') as receipt:
                receipt.write(json.dumps(native, indent=2) + '\n')
    previous = retained_bytes(retained if retained is not None else
                              tuple(ROOT / f"conformance/corpus-v{version}" for version in (1, 2, 3, 4)))
    extraction_gzip = gzip.compress(extraction, mtime=0)
    ledger_gzip = gzip.compress(ledger_bytes, mtime=0) if ledger_bytes is not None else None
    metadata: dict[str, Json] = {
        "sourceRelease": report["sourceRelease"], "sourceId": report["sourceId"],
        "sourceArchiveSha256": report["sourceArchiveSha256"],
        "sourceCatalogVersion": report["sourceCatalogVersion"], "sourceCatalog": report["sourceCatalog"],
        "sourceFamilyPolicy": report["sourceFamilyPolicy"],
        "sourceExecutionProfilePolicy": report["sourceExecutionProfilePolicy"],
        "tclDisplayPrecisionPolicy": report["tclDisplayPrecisionPolicy"],
        "tclBindingPolicy": report["tclBindingPolicy"],
        "sourceFiles": {file["file"]: file["sha256"] for file in report["files"]},
        "fileExclusionPolicy": report["fileExclusionPolicy"],
        "expressionSamplingPolicy": report["expressionSamplingPolicy"],
        "extraction": {"path": "extraction.json.gz", "sha256": digest(extraction_gzip),
                       "uncompressedSha256": digest(extraction), "recordedCases": len(captured)},
        "sourceHashes": code_hashes(), "requirementsSha256": digest(inventory_path.read_bytes()),
        "nativeReplayPassed": True, "retainedCorpora": previous,
        "byPart": dict(Counter(case["part"] for case in cases)),
        **feature_counts(cases),
    }
    if ledger_gzip is not None:
        metadata["fidelityLedger"] = {"path": "fidelity/fidelity-ledger.json.gz", "sha256": digest(ledger_gzip),
            "uncompressedSha256": digest(ledger_bytes), "mismatches": len(refusals),
            "evidence": {f"fidelity/{path}": digest(payload) for path, payload in evidence.items()}}
    output.parent.mkdir(parents=True, exist_ok=True)
    with TemporaryDirectory(prefix="freeze-corpus-", dir=output.parent) as temporary:
        stage = Path(temporary) / "corpus"
        manifest = write(stage, shards, metadata=metadata, corpus_version=5)
        (stage / "extraction.json.gz").write_bytes(extraction_gzip)
        if ledger_gzip is not None:
            (stage / "fidelity").mkdir()
            (stage / "fidelity/fidelity-ledger.json.gz").write_bytes(ledger_gzip)
            for relative, payload in evidence.items():
                destination = stage / "fidelity" / relative
                destination.parent.mkdir(parents=True, exist_ok=True)
                destination.write_bytes(payload)
        statistics: dict[str, Json] = {
            "upstreamCases": len(captured), "authoredCases": len(cases) - len(captured),
            "compressedShardBytes": sum((stage / shard["path"]).stat().st_size for shard in manifest["shards"]),
            "maximumExpandedCaseBytes": max(len(serialized(case)) for case in cases),
            "retainedBytes": sum(entry["bytes"] for entry in previous),
            "currentByteLimit": CURRENT_BYTE_LIMIT, "retainedByteLimit": RETAINED_BYTE_LIMIT,
            "directoryBytes": 0,
        }
        manifest["freezeStatistics"] = statistics
        for _attempt in range(8):
            (stage / "manifest.json").write_bytes(serialized(manifest) + b"\n")
            size = sum(path.stat().st_size for path in stage.rglob("*") if path.is_file())
            if statistics["directoryBytes"] == size:
                break
            statistics["directoryBytes"] = size
        else:
            raise ValueError("Corpus byte accounting did not stabilize")
        if size > CURRENT_BYTE_LIMIT or size + statistics["retainedBytes"] > RETAINED_BYTE_LIMIT:
            raise ValueError("Corpus byte budget exceeded; use fixed-hash release-asset storage")
        shutil.copytree(stage, output)
    return manifest


def main() -> None:
    """Freeze an actual uncapped capture with optional bound mismatch triage and retained paths."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", type=Path, required=True)
    parser.add_argument("--upstream", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--fidelity-ledger", type=Path)
    parser.add_argument("--retained", type=Path, action="append")
    parser.add_argument("--temporary-root", type=Path, required=True)
    args = parser.parse_args()
    from tools.check_resources import check_resources
    try:
        check_resources(ROOT, temporary_root=args.temporary_root)
    except (OSError, ValueError) as error:
        parser.error(str(error))
    result = freeze(args.input, args.output, upstream=args.upstream, fidelity_ledger=args.fidelity_ledger,
                    retained=tuple(args.retained) if args.retained is not None else None,
                    temporary_root=args.temporary_root,
                    storage_report=args.output.with_name(args.output.name + '-native-replay.json'))
    print(json.dumps({"recordedCases": result["recordedCases"], **result["freezeStatistics"]}))


if __name__ == "__main__":
    main()
