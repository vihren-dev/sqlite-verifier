"""Spawned development workers retain ordinary native evidence, ordered failures and bounded lifecycle."""

from copy import deepcopy
from dataclasses import replace
import json
import os
from pathlib import Path
import sys
import time

import pytest

from conformance import native_workers
from conformance.case_format import Json
from conformance.corpus import native_replay
from conformance.execution_profile import ExecutionProfile, measured_profile
from conformance.native_connection import Connection, NativeError, library_path, load_library
from conformance.native_record import record_sql
from conformance.native_storage import serialized
from conformance.native_workers import CaseInput, NativeReplayResult, replay_native_cases
from tests.runtime_support import CommandTimeout, run_command

ROOT = Path(__file__).resolve().parents[1]
pytestmark = [pytest.mark.integration, pytest.mark.conformance, pytest.mark.requires_native("sqlite3")]


@pytest.fixture
def clock_cases(tmp_path: Path) -> tuple[ExecutionProfile, list[dict[str, Json]]]:
    """Acquire two independent clocks with defaults, triggers, a transaction and UTC local-time SQL."""
    connection = Connection(load_library(library_path()), tmp_path / "measure.db")
    try:
        profile = measured_profile(connection, name="worker-clock", clock="unix-milliseconds-v1",
                                   transaction_mode="immediate")
    finally:
        connection.close()
    setup = ("CREATE TABLE t(stamp DEFAULT(unixepoch())); CREATE TABLE audit(stamp);"
        "CREATE TRIGGER log AFTER INSERT ON t BEGIN INSERT INTO audit VALUES(unixepoch()); END;")
    sql = "BEGIN IMMEDIATE; INSERT INTO t DEFAULT VALUES; SELECT stamp,datetime('now','localtime') FROM audit; COMMIT;"
    records = [record_sql(setup, sql, name=f"clock-{number}", outputs=True, profile=profile,
        setup_clock=clock, clock_values=[clock + offset * 1000 for offset in range(4)])
        for number, clock in enumerate((1700000000000, 1800000000000))]
    return profile, records


def test_real_serial_equivalence_clocks_paths_and_cleanup(
        clock_cases: tuple[ExecutionProfile, list[dict[str, Json]]], tmp_path: Path,
        monkeypatch: pytest.MonkeyPatch) -> None:
    """Distinct spawned clocks match serial evidence while preserving the parent's non-UTC timezone and inputs."""
    profile, records = clock_cases
    before = serialized(records)
    roots = [tmp_path / "serial", tmp_path / "workers"]
    for root in roots:
        root.mkdir()
    original_zone = os.environ.get("TZ")
    try:
        monkeypatch.setenv("TZ", "UTC+5")
        time.tzset()
        timezone = time.timezone
        serial_paths: list[Path] = []
        worker_paths: list[Path] = []
        native_replay(records, profile=profile, temporary_root=roots[0], fixture_paths=serial_paths)
        replay_native_cases(records, profile=profile, temporary_root=roots[1], fixture_paths=worker_paths)
        assert os.environ["TZ"] == "UTC+5" and time.timezone == timezone
        assert len(serial_paths) == len(worker_paths) == len(records)
        assert len(set(worker_paths)) == len(records)
        assert all(path.is_relative_to(roots[1]) and path.name == "case.db" for path in worker_paths)
        assert all(not path.exists() for path in serial_paths + worker_paths)
        assert all(list(root.iterdir()) == [] for root in roots) and serialized(records) == before
    finally:
        if original_zone is None:
            monkeypatch.delenv("TZ", raising=False)
        else:
            monkeypatch.setenv("TZ", original_zone)
        time.tzset()


def test_input_order_and_actual_paths_survive_failures(
        clock_cases: tuple[ExecutionProfile, list[dict[str, Json]]], tmp_path: Path) -> None:
    """A faster later profile refusal cannot replace the first input's native mismatch or lose its actual path."""
    _profile, records = clock_cases
    broken = deepcopy(records)
    broken[0]["initial"]["visible"]["schema"] = []
    broken[1]["profile"]["sourceId"] = "wrong"
    with pytest.raises(ValueError, match="Native replay changed") as serial:
        native_replay(broken)
    paths: list[Path] = []
    with pytest.raises(ValueError, match="Native replay changed") as parallel:
        replay_native_cases(broken, temporary_root=tmp_path, fixture_paths=paths)
    assert str(parallel.value) == str(serial.value)
    assert len(paths) == 1 and paths[0].is_relative_to(tmp_path) and not paths[0].parent.exists()
    assert not list(tmp_path.glob("native-workers-*"))


def test_expected_profile_refusal_matches_serial(
        clock_cases: tuple[ExecutionProfile, list[dict[str, Json]]], tmp_path: Path) -> None:
    """An explicit expected profile still refuses a different case before acquiring a fixture."""
    profile, records = clock_cases
    paths: list[Path] = []
    with pytest.raises(ValueError, match="execution profile differs"):
        replay_native_cases(records, profile=replace(profile, foreign_keys=True),
                            temporary_root=tmp_path, fixture_paths=paths)
    assert paths == [] and not list(tmp_path.glob("native-workers-*"))


def test_native_error_code_and_failure_path_survive_process_transport(tmp_path: Path) -> None:
    """A real SQLITE_FULL setup failure retains the exact native exception code and cleaned fixture path."""
    record: dict[str, Json] = {"nativeVersion": 1, "name": "full", "initial": {}, "trace": [],
        "setupCommands": ["PRAGMA max_page_count=1; CREATE TABLE t(v);"], "migrationSql": "SELECT 1;"}
    with pytest.raises(NativeError) as serial:
        native_replay([record])
    paths: list[Path] = []
    with pytest.raises(NativeError) as parallel:
        replay_native_cases([record], temporary_root=tmp_path, fixture_paths=paths)
    assert serial.value.code == parallel.value.code == 13 and str(serial.value) == str(parallel.value)
    assert len(paths) == 1 and not paths[0].parent.exists() and not list(tmp_path.glob("native-workers-*"))


def crashed_case(inputs: CaseInput) -> NativeReplayResult:
    """Leave one real open SQLite file before an abrupt crash to exercise parent-owned cleanup."""
    connection = Connection(load_library(library_path()), inputs[2] / f"crash-{os.getpid()}.db")
    connection.execute_script("CREATE TABLE t(v); INSERT INTO t VALUES(1);")
    os._exit(7)


def test_crashed_worker_fails_closed_and_removes_files(
        clock_cases: tuple[ExecutionProfile, list[dict[str, Json]]], tmp_path: Path,
        monkeypatch: pytest.MonkeyPatch) -> None:
    """An abruptly exited worker cannot pass the tier or leave its private file tree behind."""
    monkeypatch.setattr(native_workers, "_replay_case", crashed_case)
    with pytest.raises(RuntimeError, match="exited before returning evidence") as failure:
        replay_native_cases(clock_cases[1], temporary_root=tmp_path)
    assert "first case without a result: 'clock-0'" in str(failure.value)
    assert "conformance.corpus.native_replay" in str(failure.value)
    assert not list(tmp_path.glob("native-workers-*"))


def blocked_case(inputs: CaseInput) -> NativeReplayResult:
    """Finish real native replay, retain the worker group identity, then wait for the configured outer timeout."""
    result = native_workers._replay_case(inputs)
    assert result.failure is None
    (inputs[2].parent / f"worker-{os.getpid()}.json").write_text(json.dumps(
        {"pid": os.getpid(), "group": os.getpgrp()}))
    time.sleep(60)
    return result


def test_configured_timeout_stops_the_spawned_worker_group(
        clock_cases: tuple[ExecutionProfile, list[dict[str, Json]]], tmp_path: Path) -> None:
    """The same outer harness used by the real CLI kills both spawned workers without escaped processes."""
    source, driver, storage = tmp_path / "cases.json", tmp_path / "driver.py", tmp_path / "storage"
    source.write_bytes(serialized(clock_cases[1]))
    storage.mkdir()
    driver.write_text(f'''"""Run real worker fixtures until the configured outer timeout stops their group."""
import json,sys
from pathlib import Path
sys.path.insert(0,{str(ROOT)!r})
from conformance import native_workers
from tests.test_native_workers import blocked_case
if __name__ == "__main__":
    native_workers._replay_case = blocked_case
    native_workers.replay_native_cases(json.loads(Path(sys.argv[1]).read_bytes()),temporary_root=Path(sys.argv[2]))
''')
    with pytest.raises(CommandTimeout) as timeout:
        run_command([sys.executable, str(driver), str(source), str(storage)], cwd=ROOT, timeout=5)
    assert timeout.value.result.timed_out and timeout.value.result.returncode < 0
    workers = [json.loads(path.read_text()) for path in storage.glob("worker-*.json")]
    assert len(workers) == native_workers.NATIVE_WORKER_LIMIT
    assert len({worker["pid"] for worker in workers}) == len(workers)
    assert len({worker["group"] for worker in workers}) == 1
    for worker in workers:
        deadline = time.monotonic() + 3
        while True:
            state = run_command(["ps", "-p", str(worker["pid"]), "-o", "stat="], cwd=ROOT, timeout=2)
            if state.returncode or state.stdout.lstrip().startswith("Z"):
                break
            assert time.monotonic() < deadline, state.diagnostic()
            time.sleep(0.02)
    assert not list(storage.rglob("*.db"))
