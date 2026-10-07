"""Refuse independent false readiness claims and self-consistent changes to the retained build bound."""

import gzip
import hashlib
import json
from pathlib import Path
import shutil
from tempfile import TemporaryDirectory

from validate import validate


def check_mutations(source: Path) -> None:
    """Alter private receipt copies so the oracle exercises fields beyond compressed-byte integrity."""
    for defect in ("runtime", "acceptance", "build-bound", "journal-order"):
        with TemporaryDirectory(prefix="runtime-receipt-mutation-") as directory:
            root = Path(directory) / "receipt"
            shutil.copytree(source, root)
            summary = json.loads((root / "receipt.json").read_text())
            if defect == "runtime":
                summary["platforms"]["linux"]["runtime"] = "/nix/store/wrong-runtime"
            elif defect == "acceptance":
                summary["acceptancePerformed"] = True
            else:
                name = "linux/linux/receipt.json.gz" if defect == "build-bound" else "integration/merged-review-log.jsonl.gz"
                payload = gzip.decompress((root / name).read_bytes())
                if defect == "build-bound":
                    value = json.loads(payload)
                    value["buildLimitSeconds"] = 1200
                    payload = json.dumps(value).encode()
                else:
                    rows = payload.splitlines(keepends=True)
                    payload = b"".join(rows[::-1])
                compressed = gzip.compress(payload, mtime=0)
                (root / name).write_bytes(compressed)
                hashes = json.loads((root / "raw-sha256.json").read_text())
                hashes[name] = {"rawSha256": hashlib.sha256(payload).hexdigest(), "rawBytes": len(payload),
                    "gzipSha256": hashlib.sha256(compressed).hexdigest(), "gzipBytes": len(compressed)}
                (root / "raw-sha256.json").write_text(json.dumps(hashes))
            (root / "receipt.json").write_text(json.dumps(summary))
            try:
                validate(root)
            except AssertionError:
                continue
            raise AssertionError(f"Runtime readiness validator accepted {defect}")


if __name__ == "__main__":
    check_mutations(Path(__file__).parent)
    print("Refused four independent runtime readiness, build-bound and journal-order mutations.")
