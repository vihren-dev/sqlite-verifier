"""Measure complete current verification paths with new caches and one identical deadline per path."""

from collections.abc import Mapping
from dataclasses import dataclass
import gzip
import json
from pathlib import Path
from time import monotonic_ns
from typing import Literal

from migration_check.structural import Json
from tools.bundle_measurement_identity import empty_cache_directory, evidence_identity, file_sha256, host_conditions, tree_identity
from tools.bundle_measurement_inputs import require_recorded_role_roots
from tools.bundle_measurement_process import Invocation, invoke

Flow = Literal["verify", "bundle"]

CHECKER_EXIT_BY_STATUS: Mapping[Literal["VERIFIED", "VIOLATED"], int] = {"VERIFIED": 0, "VIOLATED": 2}
"""Both independent checkers return 2 for checked refutation; the public CLI returns 1."""


@dataclass(frozen=True)
class TrialSpec:
    """Share protected arguments/input identities while keeping the actual candidate CLI arguments explicit."""

    name: str
    runtime: Path
    python: Path
    observer: Path
    input_roots: tuple[Path, ...]
    common_arguments: tuple[str, ...]
    candidate_arguments: tuple[str, ...]
    expected_status: Literal["VERIFIED", "VIOLATED"]
    timeout_ns: int

    def __post_init__(self) -> None:
        """Require an integer positive common path deadline and recognized final public status."""
        if type(self.timeout_ns) is not int or self.timeout_ns <= 0:
            raise ValueError("Cold path timeout must be positive integer nanoseconds")
        if self.expected_status not in ("VERIFIED", "VIOLATED"):
            raise ValueError("Cold comparison needs VERIFIED or VIOLATED as its expected public status")
        if any(not isinstance(values, tuple) or not all(isinstance(value, str) for value in values)
               for values in (self.common_arguments, self.candidate_arguments)):
            raise ValueError("Cold command arguments must be immutable tuples of strings")
        if not isinstance(self.input_roots, tuple) or not all(isinstance(root, Path) for root in self.input_roots):
            raise ValueError("Cold source roots must be an immutable tuple of explicit paths")
        require_recorded_role_roots((*self.common_arguments, *self.candidate_arguments), (self.runtime, *self.input_roots))

    def identity(self) -> dict[str, Json]:
        """Bind all actual installed/source bytes outside measured command execution."""
        return evidence_identity(self.runtime, self.input_roots, self.observer, self.python)


@dataclass(frozen=True)
class PathObservation:
    """Whole path time includes process startup, observation and time between preparation and checking."""

    flow: Flow
    started_ns: int | None
    ended_ns: int | None
    commands: tuple[Invocation, ...]
    invalid_conditions: tuple[str, ...]
    identity_before: str
    identity_after: str | None
    artifacts: str
    cache_directories: tuple[str, ...]
    filesystem_device: int
    conditions_before: dict[str, Json]
    conditions_after: dict[str, Json]

    def wall_ns(self) -> int | None:
        """An unexecuted path has no invented duration."""
        return None if self.started_ns is None or self.ended_ns is None else self.ended_ns - self.started_ns


def retain_identity(path: Path, identity: Mapping[str, Json]) -> str:
    """Retain the complete manifest, including differences, rather than only a success digest."""
    with gzip.open(path, "wt", encoding="utf-8") as stream:
        json.dump(identity, stream, sort_keys=True)
    return str(path)


def source_hashes(runtime: dict[str, Json]) -> dict[str, str]:
    """Bind source filenames observed in installed frames to exact selected runtime file bytes."""
    files, root = runtime["files"], runtime["root"]
    if not isinstance(files, dict) or not isinstance(root, str):
        raise ValueError("Runtime identity has no file manifest")
    hashes: dict[str, str] = {}
    for relative, item in files.items():
        if not isinstance(item, dict) or not isinstance(item.get("sha256"), str) or not isinstance(item.get("resolved"), str):
            raise ValueError("Runtime file identity is malformed")
        hashes[str(Path(root) / relative)] = item["sha256"]
        hashes[item["resolved"]] = item["sha256"]
    return hashes


def execute_path(spec: TrialSpec, flow: Flow, directory: Path, baseline: dict[str, Json]) -> PathObservation:
    """Refuse changed inputs before execution and preserve all raw evidence after any invalid observation."""
    if flow not in ("verify", "bundle"):
        raise ValueError("Cold path must be verify or bundle")
    if any(directory.resolve().is_relative_to(root.resolve()) for root in (spec.runtime, *spec.input_roots)):
        raise ValueError("Trial output is inside runtime/source inputs; choose a separate evidence directory")
    directory.mkdir()
    conditions = host_conditions()
    before = spec.identity()
    before_path = retain_identity(directory / "identity-before.json.gz", before)
    caches = tuple(empty_cache_directory(directory, name) for name in ("home", "temporary", "stage-store", "agent"))
    device = directory.stat().st_dev
    if any(cache.stat().st_dev != device for cache in caches):
        raise ValueError("Cold cache directories use different filesystems; select one trial filesystem")
    invalid: list[str] = []
    if before != baseline:
        invalid.append("runtime, inputs, measurement code or Python identity changed before execution")
    commands: list[Invocation] = []
    started = ended = None
    environment = {"HOME": str(caches[0]), "TMPDIR": str(caches[1]), "LANG": "C.UTF-8",
                   "MIGRATION_CHECK_STAGE_STORE": str(caches[2])}
    launcher = (spec.runtime / "bin/migration-check").resolve(strict=True)
    runtime = before["runtime"]
    if not isinstance(runtime, dict):
        raise ValueError("Runtime identity is malformed")
    sources = source_hashes(runtime)
    expected_exit = 0 if spec.expected_status == "VERIFIED" else 1
    bundle = directory / "proof.ndjson"
    selected = [("verify", (*spec.common_arguments, *spec.candidate_arguments, "--artifacts", str(directory / "generated")),
                 "cli:verify", spec.expected_status, expected_exit)] if flow == "verify" else [
        ("prepare", (*spec.common_arguments, *spec.candidate_arguments, "--workspace", str(caches[3]), "--output", str(bundle)),
         "prepare:prepare", "PREPARED", 0),
        ("verify-bundle", (*spec.common_arguments, "--bundle", str(bundle)), "bundle:verify_bundle", spec.expected_status, expected_exit)]
    if not invalid:
        command_directories = [empty_cache_directory(directory, f"command-{index}") for index in range(len(selected))]
        launcher_hash, observer_hash = file_sha256(launcher), file_sha256(spec.observer)
        started = monotonic_ns()
        deadline = started + spec.timeout_ns
        for command_directory, (name, arguments, stage, status, code) in zip(command_directories, selected, strict=True):
            active_caches = (caches[0], caches[1], caches[3] if name == "prepare" else caches[2])
            empty = [not any(cache.iterdir()) for cache in active_caches]
            retain_identity(command_directory / "cache-before.json.gz",
                {"paths": list(map(str, active_caches)), "empty": empty, "filesystem_device": device})
            if not all(empty):
                invalid.append(f"{name} starts with nonempty active caches; invocation refused")
                break
            result = invoke(python=spec.python, observer=spec.observer, launcher=launcher, arguments=(name, *arguments),
                directory=command_directory, environment=environment, deadline_ns=deadline,
                launcher_sha256=launcher_hash, observer_sha256=observer_hash, sources=sources, required_stage=stage)
            commands.append(result)
            invalid.extend(result.invalid_conditions)
            if (result.status, result.returncode) != (status, code):
                invalid.append(f"{name} returned {result.status}/{result.returncode}; expected {status}/{code}")
            if name in ("verify", "verify-bundle") and not result.invalid_conditions:
                checker = "migration-proof-checker" if name == "verify" else "migration-bundle-checker"
                expected_checker_code = CHECKER_EXIT_BY_STATUS[spec.expected_status]
                spans = json.loads(Path(result.trace).read_text())["spans"]
                codes = [span["returncode"] for span in spans if span["stage"] == "process:" + checker]
                if codes != [expected_checker_code]:
                    invalid.append(f"{checker} result was {codes}; expected observed checker code {expected_checker_code}")
        ended = monotonic_ns()
        if ended > deadline:
            invalid.append("complete path exceeded its common deadline")
    after = spec.identity()
    after_path = retain_identity(directory / "identity-after.json.gz", after)
    if after != baseline:
        invalid.append("runtime, inputs, measurement code or Python identity changed during execution")
    artifacts = directory / "artifacts.json.gz"
    retain_identity(artifacts, tree_identity(directory))
    return PathObservation(flow, started, ended, tuple(commands), tuple(invalid), before_path, after_path,
        str(artifacts), tuple(map(str, caches)), device, conditions, host_conditions())
