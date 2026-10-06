"""Statistics per checklist condition, from the review log, to find conditions to clean up.

A condition is a cleanup candidate when it never fires although it had many chances,
when its findings are mostly rejected, when nobody acts on its findings, or when only
one of the two reviewers ever reports it. The report only suggests; the owner decides.
"""

from collections.abc import Mapping, Sequence
from dataclasses import dataclass, field
import sys

from tools.review_log import CHECKLIST, Rule, in_scope, log_path, parse_rules, read, record_findings

#: A condition that fired in none of this many chances is a candidate for removal.
NEVER_FIRED_MIN_CHANCES = 30
#: Signals about outcomes need at least this many findings with an outcome.
MIN_RESOLVED = 3
#: A condition whose resolved findings are more than this share rejected needs new wording.
REJECTED_SHARE = 0.5
#: A "should"-only condition whose resolved findings are more than this share deferred matters to nobody.
DEFERRED_SHARE = 0.5
#: Both reviewers need this many chances before their difference means anything.
REVIEWER_MIN_CHANCES = 10


@dataclass
class RuleStats:
    """What happened to one condition, counted over the reviews of its current text."""

    reviews: int = 0
    chances: int = 0
    must: int = 0
    should: int = 0
    outcomes: dict[str, int] = field(default_factory=lambda: {"fixed": 0, "rejected": 0, "deferred": 0})
    unresolved: int = 0
    chances_by_reviewer: dict[str, int] = field(default_factory=dict)
    fired_by_reviewer: dict[str, int] = field(default_factory=dict)

    @property
    def fired(self) -> int:
        """All findings of the condition."""
        return self.must + self.should


def latest_outcomes(records: Sequence[Mapping[str, object]]) -> dict[str, str]:
    """The last recorded outcome of each finding; a later resolution replaces an earlier one."""
    return {str(record["finding"]): str(record["outcome"]) for record in records
            if record.get("kind") == "resolution"}


def collect(records: Sequence[Mapping[str, object]], rules: Mapping[str, Rule]) -> dict[str, RuleStats]:
    """Count each condition over the well-formed reviews that used its current text."""
    outcomes = latest_outcomes(records)
    stats = {name: RuleStats() for name in rules}
    for record in records:
        if record.get("kind") != "review" or not record.get("well_formed"):
            continue
        versions = record.get("rules")
        files = [str(path) for path in record.get("files", []) if isinstance(path, str)] \
            if isinstance(record.get("files"), list) else []
        reviewer = str(record.get("reviewer"))
        for name, rule in rules.items():
            if not isinstance(versions, dict) or versions.get(name) != rule.version:
                continue
            counted = stats[name]
            counted.reviews += 1
            if in_scope(rule, files):
                counted.chances += 1
                counted.chances_by_reviewer[reviewer] = counted.chances_by_reviewer.get(reviewer, 0) + 1
            for finding in record_findings(record):
                if finding.get("rule") != name:
                    continue
                if finding.get("severity") == "must":
                    counted.must += 1
                else:
                    counted.should += 1
                counted.fired_by_reviewer[reviewer] = counted.fired_by_reviewer.get(reviewer, 0) + 1
                outcome = outcomes.get(str(finding.get("id")))
                if outcome in counted.outcomes:
                    counted.outcomes[outcome] += 1
                else:
                    counted.unresolved += 1
    return stats


def signals(counted: RuleStats) -> list[str]:
    """The cleanup signals of one condition, in words."""
    found: list[str] = []
    resolved = sum(counted.outcomes.values())
    if counted.chances >= NEVER_FIRED_MIN_CHANCES and counted.fired == 0:
        found.append("never fired")
    if resolved >= MIN_RESOLVED and counted.outcomes["rejected"] / resolved > REJECTED_SHARE:
        found.append("mostly rejected")
    if (counted.must == 0 and resolved >= MIN_RESOLVED
            and counted.outcomes["deferred"] / resolved > DEFERRED_SHARE):
        found.append("mostly deferred")
    if counted.unresolved:
        found.append(f"{counted.unresolved} without outcome")
    reviewers = [name for name, chances in counted.chances_by_reviewer.items() if chances >= REVIEWER_MIN_CHANCES]
    fired = [counted.fired_by_reviewer.get(name, 0) for name in reviewers]
    if len(reviewers) == 2 and min(fired) == 0 and max(fired) >= MIN_RESOLVED:
        found.append("fires with one reviewer only")
    return found


def report(stats: Mapping[str, RuleStats]) -> str:
    """A Markdown table with one row per condition."""
    lines = ["| Condition | Reviews | Chances | Fired | must / should | fixed / rejected / deferred | Signals |",
             "| --- | --- | --- | --- | --- | --- | --- |"]
    for name, counted in sorted(stats.items(), key=lambda item: int(item[0][1:])):
        outcome = counted.outcomes
        lines.append(f"| {name} | {counted.reviews} | {counted.chances} | {counted.fired} | "
                     f"{counted.must} / {counted.should} | {outcome['fixed']} / {outcome['rejected']} / "
                     f"{outcome['deferred']} | {', '.join(signals(counted)) or '-'} |")
    return "\n".join(lines)


def main(arguments: Sequence[str]) -> int:
    """`just review-stats`: print the table for the current checklist and the review log."""
    if arguments:
        print("review-stats: takes no arguments", file=sys.stderr)
        return 2
    records = read(log_path())
    reviews = [record for record in records if record.get("kind") == "review"]
    failed = sum(1 for record in reviews if not record.get("well_formed"))
    print(f"{len(reviews)} reviews, {failed} failed or malformed (not counted below).\n")
    print(report(collect(records, parse_rules(CHECKLIST.read_text(encoding="utf-8")))))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
