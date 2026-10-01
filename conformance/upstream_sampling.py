"""Sample generated name cohorts before acquisition, independently of native acceptance."""

from collections.abc import Sequence
import hashlib
from typing import TypeAlias

from conformance.case_format import Json
from conformance.native_storage import serialized

SamplingCohort: TypeAlias = tuple[str, str, int]
"""A source filename, generated-name prefix and maximum retained runtime identities."""
OPERATOR_NAMES: tuple[str, ...] = ("cat", "mul", "div", "mod", "add", "sub", "lshift", "rshift", "bitand", "bitor",
                  "less", "lesseq", "more", "moreeq", "eq1", "eq2", "ne1", "ne2", "is", "like",
                  "glob", "and", "or", "match", "regexp", "isnt")
EXPRESSION_COHORTS: tuple[SamplingCohort, ...] = (
    tuple(("e_expr.test", f"e_expr-1.{operator}.", 8) for operator in OPERATOR_NAMES)
    + tuple(("e_expr.test", f"e_expr-7.{operator}.", 8) for operator in OPERATOR_NAMES if operator not in {"and", "or"})
    + (("e_expr.test", "e_expr-8.2.", 32), ("e_expr.test", "e_expr-12.3.", 32),
       ("func.test", "func-4.17.", 16), ("func.test", "func-4.18.", 16),
       ("func.test", "func-24.7.", 16), ("func.test", "func-30.5.", 32),
       ("date.test", "date-2.2c-", 32))
)


def sampling_policy(cohorts: Sequence[SamplingCohort]) -> dict[str, Json]:
    """Declare exact cohorts and the canonical identity hash, including cohort validation."""
    for file, prefix, count in cohorts:
        if (not isinstance(file, str) or not file or not isinstance(prefix, str) or not prefix
                or type(count) is not int or count < 1):
            raise ValueError("Invalid expression sampling cohort")
    for index, (file, prefix, _count) in enumerate(cohorts):
        if any(file == other_file and (prefix.startswith(other) or other.startswith(prefix))
               for other_file, other, _other_count in cohorts[:index]):
            raise ValueError("Overlapping expression sampling cohorts")
    return {"version": 1, "algorithm": "sha256-canonical-file-id-occurrence-v1",
            "cohorts": [{"file": file, "prefix": prefix, "count": count} for file, prefix, count in cohorts]}


def select_candidates(filename: str, candidates: list[dict[str, Json]],
                      cohorts: Sequence[SamplingCohort]) -> tuple[dict[int, str], list[dict[str, Json]]]:
    """Rank complete runtime identities; exclusions and successful-record counts cannot affect selection."""
    sampling_policy(cohorts)
    rejected: dict[int, str] = {}
    report: list[dict[str, Json]] = []
    for file, prefix, count in cohorts:
        if file != filename:
            continue
        ranked = [(hashlib.sha256(serialized([filename, candidate["id"], occurrence])).hexdigest(),
                   occurrence, candidate["id"]) for occurrence, candidate in enumerate(candidates)
                  if isinstance(candidate["id"], str) and candidate["id"].startswith(prefix)]
        ranked.sort()
        rejected.update((occurrence, f"expression prefix sampling: {prefix}")
                        for _digest, occurrence, _name in ranked[count:])
        report.append({"file": filename, "prefix": prefix, "count": count, "candidateCount": len(ranked),
                       "selected": [{"id": name, "occurrence": occurrence, "sha256": digest}
                                    for digest, occurrence, name in ranked[:count]]})
    return rejected, report
