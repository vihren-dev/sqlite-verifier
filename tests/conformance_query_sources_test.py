"""Native and kernel evidence for derived sources and D3 compound metadata (ADR 0019)."""

import json
from pathlib import Path

import pytest

from conformance import authored_query_sources
from conformance.model_assertions import FOOTER, HEADER, case_assertions
from conformance.model_check import compiled_many, kernel_check, prove_all
from conformance.native_replay import prepare
from conformance.requirement_coverage import resolved_ids
from conformance.sql_text import runtime_translator

pytestmark = [pytest.mark.integration, pytest.mark.conformance, pytest.mark.kernel,
              pytest.mark.requires_lean, pytest.mark.requires_native("translation-program", "sqlite3")]
ROOT = Path(__file__).resolve().parents[1]
"""The repository root, from which the test reads conformance/requirements-3.51.0.json."""
UNMODELED = {"source-compound-representative-uncertain", "source-limit-uncertain",
             "source-limit-second-column-uncertain", "source-fallible"}
"""Source membership or evaluation failures for which D5 requires refusal."""


def test_derived_sources_native_and_kernel_verdicts(runtime_root: Path, tmp_path: Path) -> None:
    """The query-source pipeline agrees with native SQLite on supported sources and errors.
    Whole-row uncertainty and fallible evaluation stay unmodeled; the kernel checks
    both verdict classes over the runner's decoded cases and their original JSON."""
    records = authored_query_sources.records()
    assert [record["name"] for record in records] == [case.name for case in authored_query_sources.definitions()]
    resolved_ids(records, json.loads((ROOT / "conformance/requirements-3.51.0.json").read_text()))
    translator = runtime_translator(runtime_root)
    prepared = []
    for record in records:
        case, answer = prepare(record, translator)
        assert case is not None and case["outputs"] is not None, (record["name"], answer)
        prepared.append(case)
    answers = compiled_many(prepared, runtime_root, emit_lean=True)
    agreeing_cases, agreeing_terms, boundaries = [], [], []
    for index, (record, case, answer) in enumerate(zip(records, prepared, answers, strict=True)):
        unmodeled = record["name"] in UNMODELED
        assert answer["verdict"] == ("MODEL_UNSUPPORTED" if unmodeled else "AGREE"), (record["name"], answer)
        if unmodeled:
            boundaries.append(f"namespace Boundary{index}\n" +
                case_assertions(answer["caseLean"], json.dumps(case, ensure_ascii=False), expected=False) +
                "theorem sourceUnsupported : classifyCase fixture = .modelUnsupported := by decide +kernel\n"
                f"#print axioms sourceUnsupported\nend Boundary{index}\n")
        else:
            agreeing_cases.append(case)
            agreeing_terms.append(answer["caseLean"])
    assert len(boundaries) == len(UNMODELED)
    prove_all(agreeing_terms, runtime_root, tmp_path, cases=agreeing_cases, name="DerivedSources")
    destination = tmp_path / "DerivedSourceBoundaries.lean"
    destination.write_text(HEADER + "".join(boundaries) + FOOTER)
    output = kernel_check(runtime_root, destination)
    assert output.count("sourceUnsupported' depends on axioms") == len(UNMODELED)
