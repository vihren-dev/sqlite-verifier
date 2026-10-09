"""Per-condition statistics and cleanup signals from the review log."""

import pytest

from tools.review_log import Rule
from tools.review_stats import NEVER_FIRED_MIN_CHANCES, collect, report, signals

RULES = {"R1": Rule("v1", ("*",)), "R5": Rule("v5", ("*.lean",))}


def review(identifier: str, files: list[str], findings: list[tuple[str, str]], *, reviewer: str = "codex",
           versions: dict[str, str] | None = None, well_formed: bool = True) -> dict[str, object]:
    """A minimal review record."""
    return {"kind": "review", "id": identifier, "reviewer": reviewer, "files": files, "well_formed": well_formed,
            "rules": versions or {"R1": "v1", "R5": "v5"},
            "findings": [{"id": f"{identifier}#{index}", "rule": rule, "severity": severity}
                         for index, (rule, severity) in enumerate(findings, start=1)]}


def resolved(finding: str, outcome: str, date: str | None = None) -> dict[str, object]:
    """A minimal resolution record, with a date when the test needs one."""
    record: dict[str, object] = {"kind": "resolution", "finding": finding, "outcome": outcome}
    if date is not None:
        record["date"] = date
    return record


@pytest.mark.unit
def test_chances_follow_scope_and_version() -> None:
    """A review counts for a condition only with its current text, and is a chance only in its scope."""
    records = [review("a", ["x.py"], []), review("b", ["M.lean"], [("R5", "must")]),
               review("c", ["M.lean"], [], versions={"R1": "old", "R5": "v5"}),
               review("d", ["M.lean"], [], well_formed=False)]
    stats = collect(records, RULES)
    assert (stats["R1"].reviews, stats["R1"].chances) == (2, 2)
    assert (stats["R5"].reviews, stats["R5"].chances, stats["R5"].must) == (3, 2, 1)


@pytest.mark.unit
def test_never_fired_needs_enough_chances() -> None:
    """Silence is a signal only after many chances."""
    few = collect([review(str(n), ["M.lean"], []) for n in range(NEVER_FIRED_MIN_CHANCES - 1)], RULES)
    many = collect([review(str(n), ["M.lean"], []) for n in range(NEVER_FIRED_MIN_CHANCES)], RULES)
    assert "never fired" not in signals(few["R5"]) and "never fired" in signals(many["R5"])


@pytest.mark.unit
def test_outcome_signals() -> None:
    """The latest outcome counts; mostly rejected, mostly deferred and unresolved are reported."""
    records = [review("a", ["x.py"], [("R1", "should")] * 4), resolved("a#1", "fixed"), resolved("a#1", "rejected"),
               resolved("a#2", "rejected"), resolved("a#3", "deferred")]
    stats = collect(records, RULES)["R1"]
    assert stats.outcomes == {"fixed": 0, "rejected": 2, "deferred": 1} and stats.unresolved == 1
    assert signals(stats) == ["mostly rejected", "1 without outcome"]
    deferred = collect([review("b", ["x.py"], [("R1", "should")] * 3)]
                       + [resolved(f"b#{n}", "deferred") for n in (1, 2, 3)], RULES)["R1"]
    assert signals(deferred) == ["mostly deferred"]


@pytest.mark.unit
def test_one_reviewer_only() -> None:
    """A condition that only one reviewer reports, with enough chances for both, is flagged."""
    records = ([review(f"c{n}", ["x.py"], [("R1", "must")] if n < 3 else []) for n in range(10)]
               + [review(f"l{n}", ["x.py"], [], reviewer="claude") for n in range(10)])
    assert "fires with one reviewer only" in signals(collect(records, RULES)["R1"])


@pytest.mark.unit
def test_report_has_one_row_per_condition() -> None:
    """The table lists the conditions in numeric order."""
    rows = report(collect([], {"R10": Rule("v", ("*",)), "R2": Rule("v", ("*",))})).splitlines()[2:]
    assert [row.split(" | ")[0] for row in rows] == ["| R2", "| R10"]


@pytest.mark.unit
def test_latest_outcome_follows_dates() -> None:
    """A merge can put a newer resolution before an older one; the newer date still counts."""
    records = [review("d", ["x.py"], [("R1", "should")]),
               resolved("d#1", "fixed", "2026-10-08T10:00:00+00:00"),
               resolved("d#1", "rejected", "2026-10-07T10:00:00+00:00")]
    assert collect(records, RULES)["R1"].outcomes == {"fixed": 1, "rejected": 0, "deferred": 0}
    same_time = records[:1] + [resolved("d#1", "rejected", "2026-10-08T10:00:00+00:00"),
                               resolved("d#1", "fixed", "2026-10-08T10:00:00+00:00")]
    assert collect(same_time, RULES)["R1"].outcomes == {"fixed": 1, "rejected": 0, "deferred": 0}
