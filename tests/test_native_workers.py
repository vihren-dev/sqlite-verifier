"""Spawned development workers retain ordinary native evidence, ordered failures and bounded lifecycle."""

from copy import deepcopy
import fcntl
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
from conformance.native_workers import replay_native_cases
from tests.native_worker_fixtures import WORKER_CLOCKS, WORKER_START_LIMIT_SECONDS, blocked_case, crashed_case
from tests.runtime_support import CommandTimeout, run_command

ROOT = Path(__file__).resolve().parents[1]
pytestmark = [pytest.mark.integration, pytest.mark.conformance, pytest.mark.requires_native("sqlite3")]


@pytest.fixture
def clock_cases(tmp_path: Path) -> tuple[ExecutionProfile, list[dict[str, Json]]]:
    """Acquire four independent clocks with defaults, triggers, a transaction and UTC local-time SQL."""
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
        for number, clock in enumerate(WORKER_CLOCKS)]
    return profile, records


def test_real_serial_equivalence_clocks_paths_and_cleanup(
        clock_cases: tuple[ExecutionProfile, list[dict[str, Json]]], tmp_path: Path,
        monkeypatch: pytest.MonkeyPatch) -> None:
    """Distinct spawned clocks match serial evidence while preserving the parent's non-UTC timezone and inputs."""
    profile, records = clock_cases
    assert native_workers.NATIVE_WORKER_LIMIT == len(records) == len(WORKER_CLOCKS)
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
    assert len(paths) == len(records) - 1 and len(set(paths)) == len(paths)
    assert all(path.is_relative_to(tmp_path) and not path.parent.exists() for path in paths)
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


def test_crashed_worker_fails_closed_and_removes_files(
        clock_cases: tuple[ExecutionProfile, list[dict[str, Json]]], tmp_path: Path,
        monkeypatch: pytest.MonkeyPatch) -> None:
    """An abruptly exited worker cannot pass the tier or leave its private file tree behind."""
    monkeypatch.setattr(native_workers, "_replay_case", crashed_case)
    with pytest.raises(RuntimeError, match="exited before returning evidence") as failure:
        replay_native_cases(clock_cases[1], temporary_root=tmp_path)
    assert "first case without a result: 'clock-0'" in str(failure.value)
    assert "conformance.corpus.native_replay" in str(failure.value)
    workers = [json.loads(path.read_text()) for path in tmp_path.glob("crash-worker-*.json")]
    assert len(workers) == len(WORKER_CLOCKS) and len({worker["pid"] for worker in workers}) == len(workers)
    assert {worker["name"] for worker in workers} == {record["name"] for record in clock_cases[1]}
    assert not list(tmp_path.glob("native-workers-*"))


def test_configured_timeout_stops_the_spawned_worker_group(
        clock_cases: tuple[ExecutionProfile, list[dict[str, Json]]], tmp_path: Path) -> None:
    """The same outer harness used by the real CLI kills all four spawned workers without escaped processes."""
    source, driver, storage = tmp_path / "cases.json", tmp_path / "driver.py", tmp_path / "storage"
    source.write_bytes(serialized(clock_cases[1]))
    storage.mkdir()
    driver.write_text(f'''"""Run real worker fixtures until the configured outer timeout stops their group."""
import json,sys
from pathlib import Path
sys.path.insert(0,{str(ROOT)!r})
from conformance import native_workers
from tests.native_worker_fixtures import blocked_case
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
    assert {worker["name"] for worker in workers} == {record["name"] for record in clock_cases[1]}
    for worker in workers:
        deadline = time.monotonic() + WORKER_START_LIMIT_SECONDS
        with (storage / f"worker-{worker['pid']}.lock").open("rb") as activity:
            while True:
                try:
                    fcntl.flock(activity, fcntl.LOCK_EX | fcntl.LOCK_NB)
                    break
                except BlockingIOError:
                    assert time.monotonic() < deadline, f"Worker {worker['pid']} still holds its activity lock"
                    time.sleep(0.02)
    assert not list(storage.rglob("*.db"))


def test_pinned_development_corpus_loads_without_loading_workers(monkeypatch: pytest.MonkeyPatch) -> None:
    """`native_workers.load_development_corpus` starts no process pool for a pinned frozen corpus.

    A pinned corpus is only decoded, so loading workers would add process start time.
    """
    directory = ROOT / "conformance/synthetic-workload/corpus"
    expected = native_workers.load(directory)

    def refuse(*_arguments: object, **_options: object) -> None:
        """Fail the test when development loading creates loading workers."""
        raise AssertionError("loading workers started for a pinned corpus")

    monkeypatch.setattr(native_workers, "ProcessPoolExecutor", refuse)
    assert native_workers.load_development_corpus(directory) == expected
