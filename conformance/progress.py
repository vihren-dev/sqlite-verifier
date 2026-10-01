"""Join frozen-corpus verdicts to the regenerated release requirement inventory."""

import argparse
from collections import Counter, defaultdict
import hashlib
import json
from pathlib import Path

from conformance.case_format import Json
from conformance.corpus import load, replay
from conformance.requirement_coverage import inventory_rows, resolved_ids

VERDICTS = ("AGREE", "DISAGREE", "MODEL_UNSUPPORTED", "HARNESS_ERROR")


def progress(corpus: Path, requirements: Path, runtime: Path) -> dict[str, Json]:
    """Every requirement row keeps zero counts; one case can illustrate multiple requirements."""
    manifest, records = load(corpus)
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
            "runtime": str(runtime.resolve()),
            "requirementsSha256": hashlib.sha256(requirements.read_bytes()).hexdigest(),
            "frontendSha256": {str(path): hashlib.sha256(path.read_bytes()).hexdigest()
                for path in sorted(Path("migration_check").glob("*.py"))},
            "harnessSha256": {name: hashlib.sha256(Path(__file__).with_name(name).read_bytes()).hexdigest()
                for name in ("corpus.py", "native_replay.py", "progress.py", "requirement_coverage.py")},
            "denominator": len(records), "requirementInventoryCount": inventory["count"],
            "requirementMatrixRows": len(matrix), "requirementMatrix": matrix,
            "limitation": "Scenario counts do not prove entire requirements. Untagged upstream cases are not credited with file-level R-ID references.",
            **result}


def main() -> None:
    """Produce a version-specific progress report without modifying frozen cases."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--corpus", type=Path, default=Path("conformance/corpus-v3"))
    parser.add_argument("--requirements", type=Path, default=Path("conformance/requirements-3.51.0.json"))
    parser.add_argument("--runtime-root", type=Path, default=Path("build/conformance"))
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    result = progress(args.corpus, args.requirements, args.runtime_root.resolve())
    args.output.write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps({"denominator": result["denominator"], "counts": result["counts"]}))


if __name__ == "__main__":
    main()
