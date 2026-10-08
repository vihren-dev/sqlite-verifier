"""Reproduce evidence refusals after rebinding file hashes, without native or model replay."""

import gzip
import hashlib
import json
from pathlib import Path
import shutil
from tempfile import TemporaryDirectory

from validate import ROOT, validate


def check_mutations() -> None:
    """Require semantic checks to reject paths, flags, bindings, identities and summary drift."""
    for kind, target in (("duplicate-path", "darwin/receipt.json.gz"),
                         ("false-target", "linux-originals/linux/receipt.json.gz"),
                         ("changed-library", "linux-originals/linux/identity-after.json.gz"),
                         ("changed-selected-name", "darwin/report.json.gz"),
                         ("changed-summary", "acceptance.json")):
        with TemporaryDirectory(prefix="t04c-receipt-mutation-") as folder:
            candidate = Path(folder) / "report"
            shutil.copytree(ROOT, candidate)
            raw = (candidate / target).read_bytes()
            value = json.loads(gzip.decompress(raw) if target.endswith(".gz") else raw)
            if kind == "duplicate-path":
                value["phase"]["fixturePaths"][0] = value["phase"]["fixturePaths"][1]
            elif kind == "false-target":
                value["underTarget"] = False
            elif kind == "changed-library":
                next(iter(value["nativeLibraries"].values()))["sha256"] = "0" * 64
            elif kind == "changed-selected-name":
                value["generic"]["selectedNames"][0] = "changed"
            else:
                value["platforms"]["linux"]["phase_seconds"] = 1.0
            changed = json.dumps(value, sort_keys=True, ensure_ascii=False, indent=2).encode() + b"\n"
            if target.endswith(".gz"):
                compressed = gzip.compress(changed, mtime=0)
                (candidate / target).write_bytes(compressed)
                bindings = json.loads((candidate / "raw-sha256.json").read_text())
                bindings[target] = {"original_sha256": hashlib.sha256(changed).hexdigest(),
                    "original_bytes": len(changed), "sha256": hashlib.sha256(compressed).hexdigest()}
                (candidate / "raw-sha256.json").write_text(json.dumps(bindings))
            else:
                (candidate / target).write_bytes(changed)
            try:
                validate(candidate)
            except AssertionError:
                print(kind, "refused")
            else:
                raise AssertionError(f"Evidence mutation was accepted: {kind}")


if __name__ == "__main__":
    check_mutations()
