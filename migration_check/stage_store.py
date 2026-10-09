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
from pathlib import Path, PurePosixPath
import re
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


def runtime_identity(sysroot: Path, libraries: tuple[Path, Path]) -> tuple[str, ...]:
    """Resolved toolchain and libraries paths: immutable Nix outputs, not the stable links to them.

    `just build` repoints `.lake/build` at a new runtime; keys must change with it.
    """
    return (str(sysroot.resolve()), *(str(path.resolve()) for path in libraries))


def valid_manifest(manifest: object, required: tuple[str, ...]) -> dict[str, str] | None:
    """A non-empty map of safe relative paths to SHA-256 digests that includes every required file."""
    if not isinstance(manifest, dict) or not manifest:
        return None
    for name, value in manifest.items():
        path = PurePosixPath(name) if isinstance(name, str) else None
        if (path is None or path.is_absolute() or not path.parts or ".." in path.parts
                or not isinstance(value, str) or re.fullmatch(r"[0-9a-f]{64}", value) is None):
            return None
    if any(name not in manifest for name in required):
        return None
    return manifest


def stage_key(stage: str, modules: dict[str, bytes], previous: tuple[str, ...], identity: tuple[str, ...]) -> str:
    """Identify a stage by its exact sources, preceding stages and toolchain and library identity."""
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

    def restore(self, key: str, destination: Path, required: tuple[str, ...] = ()) -> bool:
        """Copy a verified entry into an empty destination; any problem is a miss.

        Every file is read and hash-checked before anything is written, so a miss
        leaves the destination untouched for fresh compilation.
        """
        entry = self.root / key
        try:
            manifest = valid_manifest(json.loads((entry / "manifest.json").read_text()), required)
            if manifest is None:
                return False
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
        staging: Path | None = None
        try:
            if entry.exists():
                return
            self.root.mkdir(parents=True, exist_ok=True)
            staging = Path(mkdtemp(prefix=".incoming-", dir=self.root))
            files = {path.relative_to(source).as_posix(): path for path in source.rglob("*") if path.is_file()}
            for name, path in files.items():
                (staging / "files" / name).parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(path, staging / "files" / name)
            manifest = {name: hashlib.sha256(path.read_bytes()).hexdigest() for name, path in files.items()}
            (staging / "manifest.json").write_text(json.dumps(manifest, sort_keys=True))
            staging.rename(entry)
        except OSError:
            # Reuse is optional: a store that cannot be written only costs the next compile.
            if staging is not None:
                shutil.rmtree(staging, ignore_errors=True)
