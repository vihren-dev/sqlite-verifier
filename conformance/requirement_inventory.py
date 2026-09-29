"""Export SQLite's own regenerated requirement database with release provenance."""

import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import sqlite3
from conformance.case_format import Json


def inventory(database: Path) -> dict[str, Json]:
    """Read generated metadata only; this SQLite connection is not a conformance execution."""
    expected = "93f1a4577785f72b4183843a7c8d33285bc36bce6f6b5258f428a6c844a0099c"
    if (database.parent / "manifest.uuid").read_text().strip() != expected:
        raise ValueError("Documentation source revision differs from the pin")
    with sqlite3.connect(f"file:{database}?mode=ro", uri=True) as connection:
        requirements = [{"id": row[0], "text": row[1], "file": row[2], "offset": row[3]}
            for row in connection.execute("SELECT reqno,reqtext,srcfile,srcseq FROM requirement ORDER BY reqno")]
        evidence = {row[0] for row in connection.execute("SELECT DISTINCT reqno FROM evidence WHERE srcclass='tcl'")}
    for item in requirements:
        item["publicTclEvidence"] = item["id"] in evidence
    return {"release": "3.51.0", "docsrcRevision": "93f1a4577785f72b4183843a7c8d33285bc36bce6f6b5258f428a6c844a0099c",
        "docsrcOriginalTarSha256": "f3a39333897823546bca5924899bafaf7f593571863666221e5a38246f065423",
        "databaseSha256": hashlib.sha256(database.read_bytes()).hexdigest(),
        "requirements": requirements, "count": len(requirements),
        "byFile": dict(sorted(Counter(item["file"] for item in requirements).items()))}


def main() -> None:
    """Persist a stable requirement inventory, keeping upstream evidence separate from our tests."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("database", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    args.output.write_text(json.dumps(inventory(args.database), indent=2) + "\n")


if __name__ == "__main__":
    main()
