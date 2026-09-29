"""Opt-in reuse of verifier-compiled stages (ADR 0003 "Approved contract reuse").

Reuse is only an optimization: every miss, mismatch or damaged entry falls back to
fresh compilation. Generated `SchemaInputs`/`SqlInputs` stages are eligible once a
store is configured. Approved closures are eligible only when listed in
`cache_eligibility.py` after a determinism review, or under an explicit
measurement-only override for the P1 experiment.
"""

from dataclasses import dataclass
import hashlib
import json
import os
from pathlib import Path
import shutil
from tempfile import mkdtemp

STORE_VARIABLE = "MIGRATION_CHECK_STAGE_STORE"
"""Environment variable naming the store directory; unset disables reuse."""

MEASUREMENT_APPROVED_VARIABLE = "MIGRATION_CHECK_MEASUREMENT_APPROVED_REUSE"
"""Set to `1` only in P1 measurements to treat approved closures as eligible."""

FORMAT = "adr3-stage-store-v1"


def digest(value: object) -> str:
    """Hash a JSON-serializable value canonically."""
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(",", ":")).encode()).hexdigest()


def stage_key(stage: str, modules: dict[str, bytes], previous: tuple[str, ...], identity: tuple[str, ...]) -> str:
    """Identify a stage by its exact sources, preceding stages and toolchain/library identity."""
    return digest({"format": FORMAT, "stage": stage, "previous": list(previous), "identity": list(identity),
                   "modules": {name: hashlib.sha256(source).hexdigest() for name, source in modules.items()}})


@dataclass(frozen=True)
class StageStore:
    """A directory of immutable stage outputs, each verified by a file-hash manifest."""

    root: Path
    approved_eligible: bool = False

    @classmethod
    def configured(cls) -> "StageStore | None":
        """The verifier's store from the environment, or None when reuse is disabled."""
        location = os.environ.get(STORE_VARIABLE)
        if not location:
            return None
        return cls(Path(location), os.environ.get(MEASUREMENT_APPROVED_VARIABLE) == "1")

    def restore(self, key: str, destination: Path) -> bool:
        """Copy a verified entry into an empty destination; any problem is a miss."""
        entry = self.root / key
        try:
            manifest: dict[str, str] = json.loads((entry / "manifest.json").read_text())
            files = {name: (entry / "files" / name).read_bytes() for name in manifest}
        except (OSError, ValueError):
            return False
        if any(hashlib.sha256(data).hexdigest() != manifest[name] for name, data in files.items()):
            return False
        for name, data in files.items():
            target = destination / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(data)
            target.chmod(0o444)
        return True

    def save(self, key: str, source: Path) -> None:
        """Publish a freshly compiled stage atomically; an existing entry is kept."""
        entry = self.root / key
        if entry.exists():
            return
        self.root.mkdir(parents=True, exist_ok=True)
        staging = Path(mkdtemp(prefix=".incoming-", dir=self.root))
        try:
            files = {path.relative_to(source).as_posix(): path for path in source.rglob("*") if path.is_file()}
            for name, path in files.items():
                (staging / "files" / name).parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(path, staging / "files" / name)
            manifest = {name: hashlib.sha256(path.read_bytes()).hexdigest() for name, path in files.items()}
            (staging / "manifest.json").write_text(json.dumps(manifest, sort_keys=True))
            staging.rename(entry)
        except OSError:
            shutil.rmtree(staging, ignore_errors=True)
