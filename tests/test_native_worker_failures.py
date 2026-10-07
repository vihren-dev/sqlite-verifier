"""An abrupt later worker failure cannot replace an earlier input's retained native failure."""

from collections.abc import Iterator
from concurrent.futures.process import BrokenProcessPool
from pathlib import Path
from unittest.mock import MagicMock

import pytest

from conformance import native_workers
from conformance.native_connection import NativeError
from conformance.native_workers import NativeReplayResult, replay_native_cases


@pytest.mark.parametrize("native_code", [None, 13])
def test_later_pool_crash_retains_earlier_input_failure(
        tmp_path: Path, monkeypatch: pytest.MonkeyPatch, native_code: int | None) -> None:
    """Ordered completed evidence retains its original failure and paths when a later result loses its worker."""
    paths = [tmp_path / f"removed-case-{index}.db" for index in range(3)]
    failure = ValueError("first input failed")

    def results() -> Iterator[NativeReplayResult]:
        """Deliver the completed prefix before the executor reports an abrupt later process failure."""
        yield NativeReplayResult("first", (paths[0],), failure, native_code)
        yield NativeReplayResult("second", (paths[1],), ValueError("later input failed"))
        yield NativeReplayResult("third", (paths[2],), None)
        raise BrokenProcessPool("later worker crashed")

    pool = MagicMock()
    pool.__enter__.return_value = pool
    pool.map.return_value = results()
    monkeypatch.setattr(native_workers, "ProcessPoolExecutor", MagicMock(return_value=pool))
    actual_paths: list[Path] = []
    with pytest.raises(NativeError if native_code is not None else ValueError) as reported:
        replay_native_cases([{"name": name} for name in ("first", "second", "third", "later")],
                            temporary_root=tmp_path, fixture_paths=actual_paths)
    assert str(reported.value) == str(failure) and actual_paths == paths
    if native_code is not None:
        assert isinstance(reported.value, NativeError) and reported.value.code == native_code
    assert not list(tmp_path.glob("native-workers-*"))


def test_crash_message_names_the_first_input_without_a_result(
        tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    """A completed successful prefix makes the diagnostic name the next input and the serial replay API."""
    def results() -> Iterator[NativeReplayResult]:
        """Retain the successful prefix before an abrupt later worker failure."""
        yield NativeReplayResult("first", (), None)
        yield NativeReplayResult("second", (), None)
        yield NativeReplayResult("third", (), None)
        raise BrokenProcessPool("later worker crashed")

    pool = MagicMock()
    pool.__enter__.return_value = pool
    pool.map.return_value = results()
    monkeypatch.setattr(native_workers, "ProcessPoolExecutor", MagicMock(return_value=pool))
    with pytest.raises(RuntimeError) as failure:
        replay_native_cases([{"name": name} for name in ("first", "second", "third", "later")],
                            temporary_root=tmp_path)
    assert "first case without a result: 'later'" in str(failure.value)
    assert "conformance.corpus.native_replay" in str(failure.value)
