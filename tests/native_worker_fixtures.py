"""Real worker fixtures retain clock identities and observable kernel resources during failure tests."""

import fcntl
import json
import os
import time

from conformance import native_workers
from conformance.native_connection import Connection, library_path, load_library
from conformance.native_workers import CaseInput, NativeReplayResult

WORKER_CLOCKS = (1700000000000, 1800000000000, 1900000000000, 2000000000000)
"""Four distinct supported clocks expose cross-process clock or timezone contamination."""
WORKER_START_LIMIT_SECONDS = 3
"""Bound worker startup and post-timeout disappearance checks in the tiny native fixtures."""


def crashed_case(inputs: CaseInput) -> NativeReplayResult:
    """Start all four workers before a real open-file crash exercises parent-owned cleanup."""
    marker = inputs[2].parent / f"crash-worker-{os.getpid()}.json"
    pending = marker.with_suffix(".pending")
    pending.write_text(json.dumps({"pid": os.getpid(), "name": inputs[0]["name"]}))
    pending.replace(marker)
    deadline = time.monotonic() + WORKER_START_LIMIT_SECONDS
    while len(list(inputs[2].parent.glob("crash-worker-*.json"))) < len(WORKER_CLOCKS):
        assert time.monotonic() < deadline, "Four native crash workers did not start within the fixture bound"
        time.sleep(0.02)
    connection = Connection(load_library(library_path()), inputs[2] / f"crash-{os.getpid()}.db")
    connection.execute_script("CREATE TABLE t(v); INSERT INTO t VALUES(1);")
    os._exit(7)


def blocked_case(inputs: CaseInput) -> NativeReplayResult:
    """Retain a kernel lock after native replay so timeout tests can observe termination without ps."""
    result = native_workers._replay_case(inputs)
    assert result.failure is None
    marker = inputs[2].parent / f"worker-{os.getpid()}.json"
    with marker.with_suffix(".lock").open("wb") as activity:
        fcntl.flock(activity, fcntl.LOCK_EX)
        pending = marker.with_suffix(".pending")
        pending.write_text(json.dumps(
            {"pid": os.getpid(), "group": os.getpgrp(), "name": inputs[0]["name"]}))
        pending.replace(marker)
        time.sleep(60)
    return result
