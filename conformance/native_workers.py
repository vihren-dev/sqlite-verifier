"""Overlap independent development-tier file replay while retaining the serial native primitive."""

from concurrent.futures import ProcessPoolExecutor
from concurrent.futures.process import BrokenProcessPool
from dataclasses import dataclass
from multiprocessing import get_context
from pathlib import Path
from tempfile import TemporaryDirectory
from typing import TypeAlias

from conformance.case_format import Json
from conformance.corpus import native_replay
from conformance.execution_profile import ExecutionProfile
from conformance.native_connection import NativeError

NATIVE_WORKER_LIMIT = 2
"""At most two development cases execute concurrently, each in a spawned process with its own timezone."""

CaseInput: TypeAlias = tuple[dict[str, Json], ExecutionProfile | None, Path]
"""Each independent case retains its exact inputs and uses private ordinary files below the selected root."""


@dataclass(frozen=True)
class NativeReplayResult:
    """Retain actual paths and failures; a native code avoids NativeError's incompatible pickle constructor."""

    name: str
    paths: tuple[Path, ...]
    failure: Exception | None
    native_code: int | None = None


def _replay_case(inputs: CaseInput) -> NativeReplayResult:
    """Use unchanged serial replay for one case and return paths even when comparison or acquisition fails."""
    record, profile, directory = inputs
    paths: list[Path] = []
    try:
        native_replay([record], profile=profile, temporary_root=directory, fixture_paths=paths)
    except NativeError as error:
        return NativeReplayResult(record["name"], tuple(paths), RuntimeError(str(error)), error.code)
    except Exception as error:
        return NativeReplayResult(record["name"], tuple(paths), error)
    return NativeReplayResult(record["name"], tuple(paths), None)


def replay_native_cases(records: list[dict[str, Json]], *, profile: ExecutionProfile | None = None,
                        temporary_root: Path | None = None, fixture_paths: list[Path] | None = None) -> None:
    """Replay every input, aggregate paths in input order, then raise the first input's failure.

    Spawned workers share the caller's process group, so the configured outer
    timeout stops the whole group. The parent removes private fixture remnants
    after a worker crash. Full native replay keeps its unchanged serial API.
    """
    first_failure: NativeReplayResult | None = None
    completed = 0
    with TemporaryDirectory(prefix="native-workers-", dir=temporary_root) as directory:
        with ProcessPoolExecutor(max_workers=NATIVE_WORKER_LIMIT, mp_context=get_context("spawn")) as executor:
            try:
                for record, result in zip(records, executor.map(_replay_case,
                        ((record, profile, Path(directory)) for record in records)), strict=True):
                    if result.name != record["name"]:
                        raise ValueError("Native worker case identity differs; check the replay inputs")
                    if fixture_paths is not None:
                        fixture_paths.extend(result.paths)
                    if first_failure is None and result.failure is not None:
                        first_failure = result
                    completed += 1
            except BrokenProcessPool as error:
                if first_failure is None:
                    name = records[completed]["name"]
                    raise RuntimeError(f"Native replay worker exited before returning evidence; first case without a result: {name!r}. "
                        "Replay this case with conformance.corpus.native_replay to inspect the failure") from error
    if first_failure is not None:
        if first_failure.native_code is not None:
            raise NativeError(first_failure.native_code, str(first_failure.failure))
        assert first_failure.failure is not None
        raise first_failure.failure
