"""Keep an unchanged valid Linux miss as the baseline for independent corruption refusals."""

import gzip
import hashlib
import json
from pathlib import Path
import shutil
from tempfile import TemporaryDirectory

from validate import Json, validate


def replace_original(root: Path, name: str, value: dict[str, Json]) -> None:
    """Rebind a private changed artifact so refusal must check its meaning, not only gzip integrity."""
    payload = json.dumps(value, ensure_ascii=False).encode()
    compressed = gzip.compress(payload, mtime=0)
    filename = name + ".gz"
    (root / filename).write_bytes(compressed)
    hashes = json.loads((root / "raw-sha256.json").read_text())
    hashes[filename] = {"rawSha256": hashlib.sha256(payload).hexdigest(), "rawBytes": len(payload),
        "gzipSha256": hashlib.sha256(compressed).hexdigest(), "gzipBytes": len(compressed)}
    (root / "raw-sha256.json").write_text(json.dumps(hashes))


def check_mutations(source: Path) -> None:
    """Require the valid baseline first, then refuse changed target, guard, paths and native identity."""
    validate(source)
    for defect in ("target", "guard", "paths", "native-library"):
        with TemporaryDirectory(prefix="linux-phase-receipt-mutation-") as directory:
            root = Path(directory) / "receipt"
            shutil.copytree(source, root)
            summary = json.loads((root / "receipt.json").read_text())
            if defect == "target":
                summary["underTarget"] = True
                (root / "receipt.json").write_text(json.dumps(summary))
            elif defect == "guard":
                value = json.loads(gzip.decompress((root / "linux/receipt.json.gz").read_bytes()))
                value["phaseLimitSeconds"] += 1
                replace_original(root, "linux/receipt.json", value)
            elif defect == "paths":
                phase = json.loads(gzip.decompress((root / "linux/phase-result.json.gz").read_bytes()))
                phase["fixturePaths"].pop()
                value = json.loads(gzip.decompress((root / "linux/receipt.json.gz").read_bytes()))
                value["phase"] = phase
                replace_original(root, "linux/phase-result.json", phase)
                replace_original(root, "linux/receipt.json", value)
            else:
                value = json.loads(gzip.decompress((root / "linux/identity-before.json.gz").read_bytes()))
                for fields in value["nativeLibraries"].values():
                    fields["sha256"] = "0" * len(fields["sha256"])
                replace_original(root, "linux/identity-before.json", value)
                replace_original(root, "linux/identity-after.json", value)
            try:
                validate(root)
            except ValueError:
                continue
            raise AssertionError(f"Linux phase validator accepted {defect}")


if __name__ == "__main__":
    check_mutations(Path(__file__).parent)
    print("Refused four independent target, guard, fixture-path and native-library mutations.")
