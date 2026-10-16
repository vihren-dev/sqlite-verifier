"""The authored coverage cases of queries, numbers and writes (ADR 0012, slices 1 to 5d).

The cases of `conformance.authored_queries`, `conformance.authored_numbers`,
`conformance.authored_writes`, `conformance.authored_row_writes`,
`conformance.authored_deletes`, `conformance.authored_joins`,
`conformance.authored_using`, `conformance.authored_right`,
`conformance.authored_merged`, `conformance.authored_keys`,
`conformance.authored_aliases`, `conformance.authored_upserts` and
`conformance.authored_algorithms` are
recorded natively as version 5 records with statement outputs, name requirement
identifiers of the pinned documentation, and replay through resolution, the
execution semantics and query evaluation. Every case agrees with the model, and the
kernel checks each verdict, so the query and number semantics and their proofs run
on the same cases. The corpus writers that publish each set as a new corpus are
checked in `tests/conformance_corpus_writers_test.py`, a scheduled suite.
"""

from concurrent.futures import ThreadPoolExecutor
import json
import os
from pathlib import Path
from types import ModuleType

import pytest

from conformance import (authored_algorithms, authored_aliases, authored_deletes, authored_joins, authored_keys,
                         authored_merged, authored_numbers, authored_queries, authored_right, authored_row_writes,
                         authored_upserts, authored_using, authored_writes)
from conformance.model_check import compiled_many, prove_batch
from conformance.native_replay import prepare
from conformance.record_parser import runtime_library
from conformance.requirement_coverage import resolved_ids

pytestmark = [pytest.mark.integration, pytest.mark.conformance, pytest.mark.kernel, pytest.mark.requires_lean,
              pytest.mark.requires_native("parser-library", "sqlite3")]
ROOT = Path(__file__).resolve().parents[1]
CASE_SETS = [authored_queries, authored_numbers, authored_writes, authored_row_writes, authored_deletes, authored_joins,
             authored_using, authored_right, authored_merged, authored_keys, authored_aliases, authored_upserts,
             authored_algorithms]
"""The authored case modules: each has `definitions` and `records`."""
PROOF_BATCH = 8
"""Cases per kernel proof file: Lean loads the imports once for each file, about 0.7 s, which
is most of the time of a one-case proof."""


@pytest.mark.parametrize("cases", CASE_SETS, ids=lambda module: module.__name__.rsplit(".", 1)[-1])
def test_coverage_cases_agree_with_kernel_proofs(cases: ModuleType, runtime_root: Path, tmp_path: Path) -> None:
    """Every case is a version 5 record with outputs and resolvable requirements, has a phase on
    each error, agrees in the compiled classifier, and has a kernel proof of its verdict."""
    records = cases.records()
    assert [record["name"] for record in records] == [case.name for case in cases.definitions()]
    resolved_ids(records, json.loads((ROOT / "conformance/requirements-3.51.0.json").read_text()))
    for record in records:
        assert record["nativeVersion"] == 5 and record["requirements"]
        assert all((event["phase"] is None) == (event["primaryCode"] == 0) for event in record["trace"])
    library = runtime_library(runtime_root)
    prepared = []
    for record in records:
        case, answer = prepare(record, library)
        assert case is not None and case["outputs"] is not None, (record["name"], answer)
        prepared.append(case)
    answers = compiled_many(prepared, runtime_root, emit_lean=True)
    assert {answer["verdict"] for answer in answers} == {"AGREE"}, answers
    starts = range(0, len(prepared), PROOF_BATCH)
    with ThreadPoolExecutor(max_workers=os.cpu_count() or 1) as pool:
        list(pool.map(lambda start: prove_batch(
            [answer["caseLean"] for answer in answers[start:start + PROOF_BATCH]], runtime_root,
            tmp_path / f"Cases{start}.lean", cases=prepared[start:start + PROOF_BATCH]), starts))
