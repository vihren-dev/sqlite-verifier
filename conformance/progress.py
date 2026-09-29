"""Join frozen-corpus verdicts to the regenerated release requirement inventory."""

import argparse
import hashlib
import json
from pathlib import Path

from conformance.case_format import Json
from conformance.corpus import load, replay

AREAS = {"datatype3.html", "lang_transaction.html", "lang_createindex.html", "lang_altertable.html"}
VERDICTS = ("AGREE", "DISAGREE", "MODEL_UNSUPPORTED", "HARNESS_ERROR")


def progress(corpus: Path, requirements: Path, runtime: Path) -> dict[str, Json]:
    """Every requirement row keeps zero counts; one case can illustrate multiple requirements."""
    manifest, records = load(corpus)
    result = replay(records, runtime)
    inventory = json.loads(requirements.read_text())
    tagged = result["byRequirement"]
    mapping = {}
    for tag in tagged:
        if tag == "UNTAGGED":
            continue
        matches = [row["id"] for row in inventory["requirements"] if row["id"].startswith(tag)]
        if len(matches) != 1:
            raise ValueError(f"Unknown or ambiguous requirement tag: {tag}")
        mapping[matches[0]] = tagged[tag]
    matrix = [{"id": row["id"], "file": row["file"], "publicTclEvidence": row["publicTclEvidence"],
               "counts": {verdict: mapping.get(row["id"], {}).get(verdict, 0) for verdict in VERDICTS}}
              for row in inventory["requirements"] if row["file"] in AREAS or row["id"] in mapping]
    return {"corpusVersion": manifest["corpusVersion"], "casesSha256": manifest["casesSha256"],
            "runtime": str(runtime.resolve()),
            "requirementsSha256": hashlib.sha256(requirements.read_bytes()).hexdigest(),
            "frontendSha256": {str(path): hashlib.sha256(path.read_bytes()).hexdigest()
                for path in sorted(Path("migration_check").glob("*.py"))},
            "denominator": len(records), "requirementInventoryCount": inventory["count"],
            "requirementMatrixRows": len(matrix), "requirementMatrix": matrix,
            "limitation": "Scenario counts do not prove entire requirements. Untagged upstream cases are not credited with file-level R-ID references.",
            **result}


def main() -> None:
    """Produce a version-specific progress report without modifying frozen cases."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--corpus", type=Path, default=Path("conformance/corpus-v2"))
    parser.add_argument("--requirements", type=Path, default=Path("conformance/requirements-3.51.0.json"))
    parser.add_argument("--runtime-root", type=Path, default=Path("build/conformance"))
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    result = progress(args.corpus, args.requirements, args.runtime_root.resolve())
    args.output.write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps({"denominator": result["denominator"], "counts": result["counts"]}))


if __name__ == "__main__":
    main()
