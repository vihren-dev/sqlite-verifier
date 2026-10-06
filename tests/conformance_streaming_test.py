"""Streaming extraction keeps historical reasons and native call boundaries intact."""

from copy import deepcopy
from pathlib import Path
import subprocess
from typing import cast

import pytest

from conformance.case_format import Json
from conformance.query_window import Token
from conformance.native_connection import SOURCE_ID
from conformance.upstream_assertions import assertions, iter_assertions
from conformance.upstream_selection import candidate_reasons
import conformance.upstream_selection as selection
import conformance.upstream_bindings as binding_observer
import conformance.upstream_pilot as upstream_pilot

pytestmark = [pytest.mark.unit, pytest.mark.conformance]


def encoded(events: list[tuple[str, ...]]) -> str:
    """Match the proxy's hex TSV without evaluating Tcl or SQL."""
    return "\n".join("\t".join(value.encode().hex() for value in event) for event in events)


def reasons(candidate: dict[str, Json]) -> list[str]:
    """Exercise cached and historical candidates under the same uncapped policy."""
    return candidate_reasons(candidate, selected=100, limit=None)


def test_iterator_is_lazy_and_matches_list_wrapper(monkeypatch: pytest.MonkeyPatch) -> None:
    """The next SQL is traced only on demand; yielded binding lists cannot change later."""
    events = [("reset",), ("sql", "db", "SELECT $setup", "0", "eval"),
              ("result", "db", "0", "1")]
    for index in range(3):
        events.extend([("begin", f"loop-{index}", str(index)),
                       ("sql", "db", f"SELECT :value{index}", "0", "eval"),
                       ("result", "db", "0", str(index)), ("end", f"loop-{index}")])
    parsed: list[str] = []
    original = binding_observer.tokens

    def observed_tokens(command: str) -> list[Token]:
        """Count command scans to rule out repeated scans of full candidate prefixes."""
        parsed.append(command)
        return original(command)

    monkeypatch.setattr(binding_observer, "tokens", observed_tokens)
    iterator = iter_assertions(encoded(events))
    first = next(iterator)
    before = deepcopy(first)
    assert parsed == ["SELECT $setup", "SELECT :value0"]
    remaining = list(iterator)
    assert first == before
    assert len(parsed) == 4
    assert [first, *remaining] == assertions(encoded(events))
    assert first["implicitBindingReasons"] == ["implicit Tcl parameter binding: $setup",
                                               "implicit Tcl parameter binding: :value0"]


def test_cache_and_legacy_fallback_keep_identical_reasons(monkeypatch: pytest.MonkeyPatch) -> None:
    """An explicit empty cache is authoritative; missing caches retain the older scan."""
    events = [("reset",), ("sql", "db", "SELECT '$literal' /* :comment */", "0", "eval"),
              ("result", "db", "0", "$literal"), ("begin", "bound", "12"),
              ("sql", "db", "SELECT @value", "0", "onecolumn"), ("result", "db", "0", "12"),
              ("end", "bound")]
    candidate = assertions(encoded(events))[0]
    historical = deepcopy(candidate)
    del historical["implicitBindingReasons"]
    assert reasons(candidate) == reasons(historical) == ["implicit Tcl parameter binding: @value"]

    def unexpected_scan(command: str) -> list[Token]:
        """Cached selection must not invoke the fallback lexer."""
        raise AssertionError(f"Unexpected prefix rescan: {command}")

    monkeypatch.setattr(selection, "tokens", unexpected_scan)
    assert reasons(candidate) == ["implicit Tcl parameter binding: @value"]
    candidate["implicitBindingReasons"] = []
    assert reasons(candidate) == []


def test_reset_inside_assertion_discards_stale_binding_markers() -> None:
    """A new database clears setup and active-command markers before the observation."""
    events = [("reset",), ("sql", "db", "SELECT $stale_setup", "0", "eval"),
              ("result", "db", "0", "1"), ("begin", "recovered", "3"),
              ("sql", "db", "SELECT :stale_active", "0", "eval"), ("result", "db", "0", "2"),
              ("reset",), ("sql", "db", "SELECT 3", "0", "eval"),
              ("result", "db", "0", "3"), ("end", "recovered")]
    candidate = assertions(encoded(events))[0]
    assert candidate["prefix"] == []
    assert candidate["commands"] == ["SELECT 3"]
    assert candidate["implicitBindingReasons"] == []
    assert reasons(candidate) == []


@pytest.mark.parametrize("control", [
    [("config", "db", "SQLITE_DBCONFIG_DQS_DDL", "1")],
    [("close", "db"), ("open", "db", "/tmp/test.db")],
    [("databases", "db", "0", "main", "/tmp/test.db", "2", "extra", "extra.db"),
     ("databases", "db", "0", "main", "/tmp/test.db")],
])
def test_control_boundaries_copy_prefix_binding_reasons(control: list[tuple[str, ...]]) -> None:
    """Moving completed calls into setup retains their markers and starts new call arrays."""
    events = [("reset", "/tmp/test.db"), ("begin", "boundary", "2"),
              ("sql", "db", "SELECT $before", "0", "eval"), ("result", "db", "0", "1"),
              *control, ("sql", "db", "SELECT @after", "0", "eval"),
              ("result", "db", "0", "2"), ("end", "boundary")]
    candidate = assertions(encoded(events))[0]
    assert candidate["prefix"][0] == "SELECT $before"
    assert candidate["commands"] == ["SELECT @after"]
    historical = deepcopy(candidate)
    del historical["implicitBindingReasons"]
    assert reasons(candidate) == reasons(historical) == ["implicit Tcl parameter binding: $before",
                                                       "implicit Tcl parameter binding: @after"]


def test_timeout_retains_completed_candidates_without_native_acquisition(
        tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    """A partial source accounts for completed identities and cannot contribute native cases."""
    source = tmp_path / "upstream" / "test"
    source.mkdir(parents=True)
    (source / "loops.test").write_text("# bounded timeout accounting fixture\n")
    events = [("reset",), ("exclude", "application callback: function")]
    for index in range(2):
        events.extend([("begin", f"generated-{index}", "1"),
                       ("sql", "db", "SELECT 1", "0", "eval"),
                       ("result", "db", "0", "1"), ("end", f"generated-{index}")])
    events.append(("begin", "unfinished", ""))

    def timed_out_run(command: list[str], **options: object) -> subprocess.CompletedProcess[str]:
        """Provide source identity, then simulate a timeout after writing complete events."""
        if "input" in options:
            return subprocess.CompletedProcess(command, 0, SOURCE_ID + "\n", "")
        environment = cast(dict[str, str], options["env"])
        Path(environment["CONFORMANCE_EVENTS"]).write_text(encoded(events) + "\n6e6f742d6865780")
        raise subprocess.TimeoutExpired(command, 60, output=b"partial runtime output", stderr=b" stopped")

    def unexpected_acquisition(*args: object, **options: object) -> dict[str, Json]:
        """No complete assertion from a partial source may be acquired."""
        raise AssertionError("A timed-out source reached native acquisition")

    monkeypatch.setattr(upstream_pilot.subprocess, "run", timed_out_run)
    monkeypatch.setattr(upstream_pilot, "record_sql", unexpected_acquisition)
    report = upstream_pilot.pilot(tmp_path / "fixture", source.parent, tmp_path / "capture", None,
        ("loops.test",), sampling=(("loops.test", "generated-", 1),))
    result = report["files"][0]
    timeout_reason = "upstream runtime exceeded 60 seconds"
    assert result["timedOut"] is True and result["excludedFile"] == timeout_reason
    assert result["runtimeExit"] is None and result["runtimeAssertions"] == 2
    assert report["recordedCases"] == result["recorded"] == 0
    assert result["runtimeDiagnostics"] == "partial runtime output stopped"
    assert result["expressionSampling"][0]["candidateCount"] == 2
    assert len(result["expressionSampling"][0]["selected"]) == 1
    assert {instance["id"] for instance in result["instances"]} == {"generated-0", "generated-1"}
    assert all({"application callback: function", timeout_reason} <= set(instance["exclusions"])
               for instance in result["instances"])
    assert sum("expression prefix sampling: generated-" in instance["exclusions"]
               for instance in result["instances"]) == 1
