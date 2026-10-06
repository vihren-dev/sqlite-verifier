"""The review log: parsing findings and conditions, records, and finding outcomes."""

from datetime import datetime, timezone
import json
import os
from pathlib import Path
import subprocess
import sys

import pytest

from tools.review_log import (Finding, in_scope, parse_findings, parse_rules, read, resolution,
                              review_record)

ROOT = Path(__file__).resolve().parents[1]
WHEN = datetime(2026, 10, 6, 12, 0, tzinfo=timezone.utc)
CHECKLIST = """## Conditions

**R1. One.** Text one.
*Applies to:* all files.

**R2. Two.** Text two.
*Applies to:* `*.lean`, `tools/*.py`.

## Output format
- R<number> <must|should> <path>:<line> text
"""


@pytest.mark.unit
def test_parse_findings() -> None:
    """Each finding line is read with its text; the template line in the format is not a finding."""
    findings, well_formed = parse_findings("Summary\n- R2 must A.lean:4 Missing words. Fix: add them.\n")
    assert well_formed and findings == [Finding("R2", "must", "A.lean", 4, "Missing words. Fix: add them.")]
    assert parse_findings("No findings.\n") == ([], True)
    assert parse_findings("Looks fine.\n") == ([], False)


@pytest.mark.unit
def test_parse_rules_and_scope() -> None:
    """Each condition has a scope; a changed text gives a new version, an unchanged one keeps it."""
    rules = parse_rules(CHECKLIST)
    assert rules["R1"].scope == ("*",) and rules["R2"].scope == ("*.lean", "tools/*.py")
    assert in_scope(rules["R2"], ["SqliteVerifier/Model.lean"]) and not in_scope(rules["R2"], ["README.md"])
    changed = parse_rules(CHECKLIST.replace("Text two.", "Text two, clearer."))
    assert changed["R1"].version == rules["R1"].version and changed["R2"].version != rules["R2"].version


@pytest.mark.unit
def test_review_record() -> None:
    """A record keeps the commit, the files, the condition versions and numbered findings."""
    record = review_record(commit="ab" * 20, revision="@-", reviewer="codex", caller="claude",
                           files=["A.lean"], checklist=CHECKLIST, exit_code=1, when=WHEN,
                           output="- R2 must A.lean:4 Missing words.\n- R1 should A.lean:9 Literal.\n")
    assert record["id"] == "20261006T120000Z-abababab"
    assert record["rules"] == {name: rule.version for name, rule in parse_rules(CHECKLIST).items()}
    assert [finding["id"] for finding in record["findings"]] == [f"{record['id']}#1", f"{record['id']}#2"]


@pytest.mark.unit
@pytest.mark.parametrize("finding,outcome,reason,message", [
    ("r#1", "ignored", "", "unknown outcome"),
    ("r#1", "rejected", " ", "needs a reason"),
    ("r#9", "fixed", "", "no finding"),
])
def test_resolution_rejects(finding: str, outcome: str, reason: str, message: str) -> None:
    """An unknown outcome, a rejection without a reason, or an unknown finding is refused."""
    records = [{"kind": "review", "findings": [{"id": "r#1"}]}]
    with pytest.raises(ValueError, match=message):
        resolution(records, finding, outcome, reason, WHEN)


@pytest.mark.integration
def test_resolve_command_appends(tmp_path: Path) -> None:
    """`just review-resolve` adds one resolution line for a known finding."""
    log = tmp_path / "log.jsonl"
    log.write_text(json.dumps({"kind": "review", "findings": [{"id": "r#1"}]}) + "\n")
    environment = {**os.environ, "SQLITE_VERIFIER_REVIEW_LOG": str(log)}
    result = subprocess.run([sys.executable, "-m", "tools.review_log", "r#1", "rejected", "a test fixture"],
                            cwd=ROOT, env=environment, capture_output=True, text=True, timeout=15, check=False)
    assert result.returncode == 0, result.stderr
    assert read(log)[-1] | {"date": None} == {"kind": "resolution", "finding": "r#1", "outcome": "rejected",
                                              "reason": "a test fixture", "date": None}
