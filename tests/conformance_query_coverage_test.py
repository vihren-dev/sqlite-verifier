"""The authored coverage cases of queries, numbers, writes and index forms (ADR 0012, slices 1 to
6g; ADR 0014).

The cases of `conformance.authored_queries`, `conformance.authored_numbers`,
`conformance.authored_writes`, `conformance.authored_row_writes`,
`conformance.authored_deletes`, `conformance.authored_joins`,
`conformance.authored_using`, `conformance.authored_right`,
`conformance.authored_merged`, `conformance.authored_keys`,
`conformance.authored_aliases`, `conformance.authored_upserts`,
`conformance.authored_algorithms`, `conformance.authored_fromless`,
`conformance.authored_json`, `conformance.authored_json_functions`,
`conformance.authored_json_each`, `conformance.authored_default_writes`,
`conformance.authored_clock`, `conformance.authored_date_functions` and
`conformance.authored_date_modifiers` (these three under the controlled clock), and
`conformance.authored_indexes`, `conformance.authored_without_rowid`,
`conformance.authored_collations`, `conformance.authored_checks`,
`conformance.authored_generated`, `conformance.authored_strict` and
`conformance.authored_drops` (ADR 0014, slices 1 to 7), and
`conformance.authored_text_functions`, `conformance.authored_numeric_functions`,
`conformance.authored_json_edits`, `conformance.authored_jsonb`,
`conformance.authored_aggregates` and `conformance.authored_printf` (ADR 0015, slices 1 to 6),
and `conformance.authored_subqueries`, `conformance.authored_expression_forms` and
`conformance.authored_distinct_having`, `conformance.authored_foreign_keys` and
`conformance.authored_triggers` and `conformance.authored_possible_results` (ADR 0018,
slices 1 to 6; the foreign keys and the triggers under a profile with foreign keys on), and
`conformance.authored_parameters` (ADR 0019, slice 1), which bind values to parameters,
`conformance.authored_pragmas` (ADR 0019, slice 2; its recursive trigger case under a profile
with recursive triggers on) and `conformance.authored_compound` (ADR 0019, slice 3) are
recorded natively as version 5 records with statement outputs, and the cases of
`conformance.authored_after_error` as version 6 records, which run on after an error; they name requirement
identifiers of the pinned documentation, and replay through resolution, the
execution semantics and query evaluation. Every case agrees with the model, and the
kernel checks each verdict, so the query and number semantics and their proofs run
on the same cases. The corpus writers that publish each set as a new corpus are
checked in `tests/conformance_corpus_writers_test.py`, a scheduled suite.
"""

import json
from pathlib import Path
from types import ModuleType

import pytest

from conformance import (authored_after_error, authored_algorithms, authored_aliases, authored_checks, authored_clock, authored_collations,
                         authored_date_functions, authored_date_modifiers, authored_default_writes, authored_deletes,
                         authored_drops, authored_generated,
                         authored_fromless, authored_indexes, authored_joins, authored_json, authored_json_each,
                         authored_aggregates, authored_printf, authored_json_edits, authored_jsonb, authored_json_functions,
                         authored_subqueries, authored_expression_forms, authored_distinct_having,
                         authored_foreign_keys, authored_triggers, authored_possible_results, authored_parameters,
                         authored_pragmas, authored_compound, authored_keys,
                         authored_merged, authored_numbers,
                         authored_queries, authored_right, authored_row_writes, authored_strict,
                         authored_text_functions, authored_numeric_functions, authored_upserts,
                         authored_using, authored_without_rowid, authored_writes)
from conformance.model_check import compiled_many, prove_all
from conformance.native_replay import prepare
from conformance.sql_text import runtime_translator
from conformance.requirement_coverage import resolved_ids

pytestmark = [pytest.mark.integration, pytest.mark.conformance, pytest.mark.kernel, pytest.mark.requires_lean,
              pytest.mark.requires_native("translation-program", "sqlite3")]
ROOT = Path(__file__).resolve().parents[1]
CASE_SETS = [authored_queries, authored_numbers, authored_writes, authored_row_writes, authored_deletes, authored_joins,
             authored_using, authored_right, authored_merged, authored_keys, authored_aliases, authored_upserts,
             authored_algorithms, authored_fromless, authored_json,
             authored_json_functions, authored_json_each,
             authored_default_writes, authored_clock, authored_date_functions, authored_date_modifiers,
             authored_indexes, authored_without_rowid, authored_collations, authored_checks, authored_generated,
             authored_strict, authored_drops, authored_text_functions, authored_numeric_functions,
             authored_json_edits, authored_jsonb, authored_aggregates, authored_printf, authored_subqueries,
             authored_expression_forms, authored_distinct_having, authored_foreign_keys, authored_triggers,
             authored_possible_results, authored_parameters, authored_compound, authored_pragmas,
             authored_after_error]
"""The authored case modules: each has `definitions` and `records`."""


@pytest.mark.parametrize("cases", CASE_SETS, ids=lambda module: module.__name__.rsplit(".", 1)[-1])
def test_coverage_cases_agree_with_kernel_proofs(cases: ModuleType, runtime_root: Path, tmp_path: Path) -> None:
    """Every case is a version 5 record with outputs, or a version 6 record of
    `conformance.authored_after_error`, with resolvable requirements, has a phase on each error,
    agrees in the compiled classifier, and has a kernel proof of its verdict."""
    records = cases.records()
    assert [record["name"] for record in records] == [case.name for case in cases.definitions()]
    resolved_ids(records, json.loads((ROOT / "conformance/requirements-3.51.0.json").read_text()))
    for record in records:
        assert record["nativeVersion"] == (6 if cases is authored_after_error else 5) and record["requirements"]
        assert all((event["phase"] is None) == (event["primaryCode"] == 0) for event in record["trace"])
    translator = runtime_translator(runtime_root)
    prepared = []
    for record in records:
        case, answer = prepare(record, translator)
        assert case is not None and case["outputs"] is not None, (record["name"], answer)
        prepared.append(case)
    answers = compiled_many(prepared, runtime_root, emit_lean=True)
    assert {answer["verdict"] for answer in answers} == {"AGREE"}, answers
    prove_all([answer["caseLean"] for answer in answers], runtime_root, tmp_path, cases=prepared)
