"""Source and affected join mutants change their native cases' classification (ADR 0019, D5)."""

from pathlib import Path

import pytest

from conformance import authored_query_sources, authored_right, query_source_mutants, right_mutants
from conformance.native_replay import prepare
from conformance.resolve_mutants import AGREE, UNSUPPORTED, measure
from conformance.sql_text import runtime_translator
from tests.mutant_sets import measure_set

pytestmark = [pytest.mark.integration, pytest.mark.conformance,
              pytest.mark.requires_lean, pytest.mark.requires_native("translation-program", "sqlite3")]
ROOT = Path(__file__).resolve().parents[1]
"""The packages copied by the existing mutant runner."""


@pytest.mark.parametrize("name", list(query_source_mutants.MUTANTS))
def test_derived_source_mutant_changes_a_verdict(runtime_root: Path, name: str) -> None:
    """Source scope, each column's affinity/collation and whole-row certainty remain observable.
    Each invocation changes one rule, so the test runs one mutation build at a time."""
    wanted = query_source_mutants.TARGETS[name]
    raw = authored_query_sources.records([case for case in authored_query_sources.definitions() if case.name in wanted])
    cases = []
    for record in raw:
        case, answer = prepare(record, runtime_translator(runtime_root))
        assert case is not None, answer
        cases.append(case)
    expected = UNSUPPORTED if name == "source_uncertainty_ignored" else AGREE
    result = measure(cases, ROOT, runtime_root, {name: query_source_mutants.MUTANTS[name]},
                     {name: wanted}, expected=expected)
    assert result[name]["killed"], result


@pytest.mark.parametrize("name", ["right_drops_unmatched", "right_pads_own_width"])
def test_source_join_padding_mutant_changes_a_verdict(runtime_root: Path, name: str) -> None:
    """The RIGHT JOIN mutants still detect missing rows and wrong padding after source outer-cell support.
    Select one existing mutant per invocation to bound its build concurrency."""
    measure_set(runtime_root, [authored_right], [({name: right_mutants.MUTANTS[name]},
                                               {name: right_mutants.TARGETS[name]})])
