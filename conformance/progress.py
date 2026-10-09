"""Join frozen-corpus verdicts to the regenerated release requirement inventory."""

import argparse
from collections import Counter, defaultdict
import hashlib
import json
from pathlib import Path
import sys

from belay.sqlite.parser_library import library_name
from conformance.case_format import Json
from conformance.corpus import load, replay
from conformance.corpus_evidence import FEATURE_LABEL_VIEWS, feature_label_view
from conformance.corpus_shards import source_path
from conformance.requirement_coverage import inventory_rows, resolved_ids

VERDICTS = ("AGREE", "DISAGREE", "MODEL_UNSUPPORTED", "HARNESS_ERROR")
ROOT = Path(__file__).resolve().parents[1]
RUNTIME_FILES = (f"lib/{library_name(sys.platform)}", ".lake/build/bin/conformance-runner")
"""The parser library and the compiled model, which a progress report binds by digest."""


def digest(path: Path) -> str:
    """Bind a report to actual bytes; absent inputs cannot produce an identity."""
    return hashlib.sha256(path.read_bytes()).hexdigest()


def totals(counts: Counter[str]) -> dict[str, Json]:
    """Every view names its scenario denominator and keeps zero verdicts visible."""
    return {"denominator": sum(counts.values()),
            "counts": {verdict: counts[verdict] for verdict in VERDICTS}}


def views(manifest: dict[str, Json], records: list[dict[str, Json]],
          answers: list[dict[str, Json]], corpus: Path) -> dict[str, Json]:
    """Parts/shards partition cases; file, case and unscoped scenario labels stay separate."""
    parts: dict[str, Counter[str]] = defaultdict(Counter)
    labels: dict[str, dict[str, Counter[str]]] = {view: defaultdict(Counter) for view in FEATURE_LABEL_VIEWS}
    for record, answer in zip(records, answers, strict=True):
        if record["name"] != answer["name"] or answer["verdict"] not in VERDICTS:
            raise ValueError("Progress case identities or verdicts differ")
        verdict = answer["verdict"]
        parts[record.get("part", "legacy")][verdict] += 1
        view = feature_label_view(record)
        for feature in set(record.get("features", [])):
            labels[view][feature][verdict] += 1
    declarations = manifest.get("shards", [{"path": "cases.jsonl.gz", "source": "legacy",
        "part": "legacy", "recordedCases": len(records), "casesSha256": manifest["casesSha256"]}])
    shards: list[Json] = []
    offset = 0
    for index, shard in enumerate(declarations):
        end = offset + shard["recordedCases"]
        selected = answers[offset:end]
        if len(selected) != shard["recordedCases"]:
            raise ValueError("Progress shard denominator differs")
        shards.append({**shard, "index": index, "sha256": digest(source_path(corpus, shard["path"])),
                       **totals(Counter(answer["verdict"] for answer in selected))})
        offset = end
    if offset != len(records):
        raise ValueError("Progress shards do not partition corpus")
    return {"byPart": {key: totals(value) for key, value in sorted(parts.items())},
            **{view: {label: totals(counts) for label, counts in sorted(values.items())}
               for view, values in labels.items()}, "byShard": shards}


def progress(corpus: Path, requirements: Path, runtime: Path) -> dict[str, Json]:
    """Every requirement row keeps zero counts; one case can illustrate multiple requirements."""
    manifest, records = load(corpus)
    runtime_hashes = {relative: digest(runtime / relative) for relative in RUNTIME_FILES}
    inventory = json.loads(requirements.read_text())
    identities = resolved_ids(records, inventory)
    result = replay(records, runtime)
    mapping: dict[str, Counter[str]] = defaultdict(Counter)
    for case_ids, answer in zip(identities, result["cases"], strict=True):
        for identity in case_ids:
            mapping[identity][answer["verdict"]] += 1
    matrix = [{"id": row["id"], "file": row["file"], "publicTclEvidence": row["publicTclEvidence"],
               "counts": {verdict: mapping.get(row["id"], {}).get(verdict, 0) for verdict in VERDICTS}}
              for row in inventory_rows(inventory)]
    return {"corpusVersion": manifest["corpusVersion"], "casesSha256": manifest["casesSha256"],
            "corpusManifestSha256": digest(corpus / "manifest.json"),
            "executionProfiles": manifest.get("executionProfiles", []),
            "corpusEvidence": {key: manifest[key] for key in ("extraction", "fidelityLedger") if key in manifest},
            "runtime": str(runtime.resolve()),
            "runtimeSha256": runtime_hashes,
            "requirementsSha256": digest(requirements),
            "frontendSha256": {str(path.relative_to(ROOT)): digest(path)
                for path in sorted((ROOT / "belay/sqlite").glob("*.py"))},
            "harnessSha256": {path.name: digest(path)
                for path in sorted((ROOT / "conformance").glob("*.py"))},
            "denominator": len(records), "requirementInventoryCount": inventory["count"],
            "requirementMatrixRows": len(matrix), "requirementMatrix": matrix,
            "limitation": "Counts describe overlapping scenario labels, not measured SQL execution coverage or model support. Source-file labels count file membership; case labels are scenario annotations; historical labels without scope remain unscoped. Untagged upstream cases receive no file-level R-ID credit.",
            **result, **views(manifest, records, result["cases"], corpus)}


def main() -> None:
    """Produce a version-specific progress report without modifying frozen cases."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--corpus", type=Path, default=Path("conformance/corpus-v5"))
    parser.add_argument("--requirements", type=Path, default=Path("conformance/requirements-3.51.0.json"))
    parser.add_argument("--runtime-root", type=Path, default=Path("build/conformance"))
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    result = progress(args.corpus, args.requirements, args.runtime_root.resolve())
    args.output.write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps({"denominator": result["denominator"], "counts": result["counts"]}))


if __name__ == "__main__":
    main()
