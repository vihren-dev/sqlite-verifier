"""The mutant tables name what each mutant guards (`conformance.mutant_guards`).

A mutant that survives shows that a rule, a restriction or an admission obligation
is untested; the link says which one. The check runs over the real mutant tables and
the model sources, so a renamed declaration or a removed restriction id breaks the
link at once, and over small sources that show each kind of broken link.
"""

from pathlib import Path
from types import ModuleType

import pytest

from conformance import (algorithm_mutants, alias_mutants, clock_mutants, delete_mutants, fromless_mutants, join_mutants,
                         json_each_mutants, json_function_mutants, json_mutants, key_mutants, merged_mutants,
                         number_mutants, obligation_mutants, query_mutants, resolve_mutants, right_mutants,
                         row_write_mutants, upsert_mutants, using_mutants, write_mutants)
from conformance.mutant_guards import guard_problems, obligation_problems
from tests.restriction_registry_test import registry_ids

pytestmark = [pytest.mark.unit]
ROOT = Path(__file__).resolve().parents[1]


@pytest.mark.parametrize("table", [resolve_mutants, query_mutants, number_mutants, write_mutants, row_write_mutants,
                                   delete_mutants, join_mutants, using_mutants, right_mutants, merged_mutants,
                                   key_mutants, alias_mutants, upsert_mutants, algorithm_mutants, fromless_mutants,
                                   json_mutants, json_function_mutants, json_each_mutants, clock_mutants,
                                   obligation_mutants],
                         ids=lambda table: table.__name__.rsplit(".", 1)[1])
def test_every_mutant_names_what_it_guards(table: ModuleType) -> None:
    """Every mutant of the table has a guard, and every guard names something that exists."""
    problems = guard_problems(table.MUTANTS, table.GUARDS, ROOT / "packages",
                              set(registry_ids().values()), set(obligation_mutants.OBLIGATIONS))
    assert not problems, problems


def test_every_obligation_conjunct_has_a_mutant_or_a_reason() -> None:
    """Every conjunct of `obligation_mutants.OBLIGATIONS` is in its declaration and has either a
    mutant or an entry of `COVERED_ELSEWHERE` with an existing restriction or a reason."""
    problems = obligation_problems(obligation_mutants.OBLIGATIONS, obligation_mutants.COVERED_ELSEWHERE,
                                   obligation_mutants.GUARDS, ROOT / "packages", set(registry_ids().values()))
    assert not problems, problems


def test_broken_obligation_entries_are_reported(tmp_path: Path) -> None:
    """A conjunct outside its declaration, a conjunct with neither or both kinds of evidence, and a
    covered entry of no conjunct, of an unknown restriction or without a reason are each reported."""
    (tmp_path / "Ready.lean").write_text("def ready : Bool :=\n  first && second\n\ndef other : Bool := third\n")
    obligations = {"first": ("Ready.lean", "ready", "first"), "second": ("Ready.lean", "ready", "second"),
                   "third": ("Ready.lean", "ready", "third"), "fourth": ("Ready.lean", "ready", "first")}
    covered = {"first": "reason:guaranteed", "second": "restriction:missing", "stray": "reason:"}
    problems = obligation_problems(obligations, covered, {"mutant": "obligation:first"}, tmp_path, {"real-value"})
    assert problems == [
        "first: needs exactly one of a mutant and an entry of COVERED_ELSEWHERE",
        "third: its text is not inside the declaration ready of Ready.lean",
        "third: needs exactly one of a mutant and an entry of COVERED_ELSEWHERE",
        "fourth: needs exactly one of a mutant and an entry of COVERED_ELSEWHERE",
        "second: restriction:missing is neither restriction: with a registry id nor reason: with text",
        "stray: covered, but not an obligation conjunct",
        "stray: reason: is neither restriction: with a registry id nor reason: with text",
    ]


def test_broken_links_are_reported(tmp_path: Path) -> None:
    """A guard of the wrong declaration, an unknown restriction or obligation, an unknown kind,
    a mutant without a guard and a guard without a mutant are each reported."""
    (tmp_path / "Rules.lean").write_text("def first : Nat := 1\n\ndef second : Nat := 2\n")
    mutants = {name: ("Rules.lean", "def second : Nat := 2", "def second : Nat := 3")
               for name in ("wrong_rule", "right_rule", "restriction", "obligation", "kind", "unguarded")}
    guards = {"wrong_rule": "rule:first", "right_rule": "rule:second", "restriction": "restriction:missing",
              "obligation": "obligation:missing", "kind": "law:second", "stray": "rule:second"}
    problems = guard_problems(mutants, guards, tmp_path, {"real-value"}, {"present"})
    assert problems == [
        "unguarded: no guard; add it to GUARDS",
        "stray: guard of no mutant; remove it from GUARDS",
        "wrong_rule: its text is not inside the declaration first of Rules.lean",
        "restriction: missing is not a restriction id of RestrictionKind.id",
        "obligation: missing is not an obligation conjunct",
        "kind: law:second does not start with rule:, restriction: or obligation:",
    ]
