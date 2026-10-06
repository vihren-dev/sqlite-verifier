"""The review log: one JSON line per review and per finding outcome.

`tools/review_stats.py` reads this log to find checklist conditions that never fire,
that are mostly rejected, or that nobody acts on. The log lives in the repository,
so every agent and workspace adds to one history.
"""

import argparse
from collections.abc import Iterable, Mapping, Sequence
from dataclasses import asdict, dataclass
from datetime import datetime, timezone
import fnmatch
import hashlib
import json
import os
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
CHECKLIST = ROOT / "docs" / "review-checklist.md"
#: The log file; tests point the variable at a temporary file.
LOG_VARIABLE = "SQLITE_VERIFIER_REVIEW_LOG"
DEFAULT_LOG = ROOT / "reviews" / "log.jsonl"
#: What can happen to a finding. "rejected" and "deferred" need a reason.
OUTCOMES = ("fixed", "rejected", "deferred")

FINDING = re.compile(r"^\s*[-*]\s*(R\d+)\s+(must|should)\s+(\S+?):(\d+)\b[ \t]*(.*)$", re.MULTILINE)
NO_FINDINGS = re.compile(r"^\s*No findings\.\s*$", re.MULTILINE)
RULE = re.compile(r"^\*\*(R\d+)\.", re.MULTILINE)
SCOPE = re.compile(r"^\*Applies to:\*\s*(.+?)\.?\s*$", re.MULTILINE)


@dataclass(frozen=True)
class Finding:
    """One violation that a reviewer reported, in the checklist's line format."""

    rule: str
    severity: str
    path: str
    line: int
    text: str


@dataclass(frozen=True)
class Rule:
    """One checklist condition: a hash of its text, so a rewrite restarts its statistics,
    and the file patterns it applies to (`*` for all files)."""

    version: str
    scope: tuple[str, ...]


def parse_findings(output: str) -> tuple[list[Finding], bool]:
    """The findings in a review, and whether the review is well formed (findings or `No findings.`)."""
    findings = [Finding(rule, severity, path, int(line), text.strip())
                for rule, severity, path, line, text in FINDING.findall(output)]
    return findings, bool(findings) or bool(NO_FINDINGS.search(output))


def parse_rules(checklist: str) -> dict[str, Rule]:
    """Each condition of the checklist with its version and scope."""
    conditions = checklist.split("## Output format")[0]
    starts = [match.start() for match in RULE.finditer(conditions)] + [len(conditions)]
    rules: dict[str, Rule] = {}
    for start, end in zip(starts, starts[1:]):
        text = conditions[start:end].strip()
        heading = RULE.match(text)
        if heading is None:
            continue
        identifier = heading.group(1)
        scope_match = SCOPE.search(text)
        scope_text = scope_match.group(1) if scope_match else "all files"
        scope = tuple(re.findall(r"`([^`]+)`", scope_text)) or ("*",)
        version = hashlib.sha256(" ".join(text.split()).encode()).hexdigest()[:12]
        rules[identifier] = Rule(version, scope)
    return rules


def in_scope(rule: Rule, files: Iterable[str]) -> bool:
    """Whether a change to `files` gave `rule` a chance to fire."""
    return any(fnmatch.fnmatch(path, pattern) for path in files for pattern in rule.scope)


def review_record(*, commit: str, revision: str, reviewer: str, caller: str, files: Sequence[str],
                  checklist: str, exit_code: int, output: str, when: datetime) -> dict[str, object]:
    """The log line of one review; each finding gets an id for its later outcome."""
    findings, well_formed = parse_findings(output)
    identifier = f"{when.strftime('%Y%m%dT%H%M%SZ')}-{commit[:8]}"
    return {"kind": "review", "id": identifier, "date": when.isoformat(timespec="seconds"),
            "commit": commit, "revision": revision, "reviewer": reviewer, "caller": caller,
            "files": list(files), "exit": exit_code, "well_formed": well_formed,
            "rules": {name: rule.version for name, rule in parse_rules(checklist).items()},
            "findings": [{"id": f"{identifier}#{index}", **asdict(finding)}
                         for index, finding in enumerate(findings, start=1)]}


def log_path() -> Path:
    """The log file in use: `reviews/log.jsonl`, or the file that `SQLITE_VERIFIER_REVIEW_LOG`
    names, so that tests never write to the repository's log."""
    return Path(os.environ.get(LOG_VARIABLE, str(DEFAULT_LOG)))


def append(record: Mapping[str, object], path: Path) -> None:
    """Add one record as one line. Records are only added, never changed, so the log is a
    complete history for the statistics, and concurrent workspaces merge by joining lines."""
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a", encoding="utf-8") as stream:
        stream.write(json.dumps(record, ensure_ascii=False, sort_keys=True) + "\n")


def read(path: Path) -> list[dict[str, object]]:
    """All records, oldest first, as the statistics and `review-resolve` need them; an absent
    log has none."""
    if not path.exists():
        return []
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]


def record_findings(record: Mapping[str, object]) -> list[dict[str, object]]:
    """The findings of one review record, in order; other records have none."""
    findings = record.get("findings") if record.get("kind") == "review" else None
    return [item for item in findings if isinstance(item, dict)] if isinstance(findings, list) else []


def finding_ids(records: Sequence[Mapping[str, object]]) -> set[str]:
    """The ids of all findings in the review records."""
    return {str(item["id"]) for record in records for item in record_findings(record) if "id" in item}


def resolution(records: Sequence[Mapping[str, object]], finding: str, outcome: str, reason: str,
               when: datetime) -> dict[str, object]:
    """The log line of one finding's outcome, after checking that the finding exists."""
    if outcome not in OUTCOMES:
        raise ValueError(f"unknown outcome {outcome!r}; use one of {', '.join(OUTCOMES)}")
    if outcome != "fixed" and not reason.strip():
        raise ValueError(f"outcome {outcome!r} needs a reason")
    if finding not in finding_ids(records):
        raise ValueError(f"no finding with id {finding!r} in {log_path()}; copy the id from the "
                         f"'review: finding ...' lines that `just review` printed")
    return {"kind": "resolution", "finding": finding, "outcome": outcome, "reason": reason.strip(),
            "date": when.isoformat(timespec="seconds")}


def main(arguments: Sequence[str]) -> int:
    """`just review-resolve FINDING OUTCOME [REASON]`: record what happened to one finding."""
    parser = argparse.ArgumentParser(prog="just review-resolve", description=main.__doc__)
    parser.add_argument("finding", help="finding id, as printed by `just review`")
    parser.add_argument("outcome", choices=OUTCOMES)
    parser.add_argument("reason", nargs="?", default="", help="required for rejected and deferred")
    options = parser.parse_args(arguments)
    path = log_path()
    try:
        record = resolution(read(path), options.finding, options.outcome, options.reason,
                            datetime.now(timezone.utc))
    except ValueError as error:
        print(f"review-resolve: {error}", file=sys.stderr)
        return 2
    append(record, path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
