"""The corpus writers of the authored coverage cases (ADR 0008 and ADR 0012).

Each writer (`conformance.resolution_evidence` and the `*_evidence` modules of the query,
number, write, join and obligation cases) records its cases natively and publishes them
through `conformance.authored_evidence.publish`. A round trip writes a new corpus, reads
it back unchanged, replays it natively and refuses to replace it. The corpora that the
writers produced are frozen and locked, and `tests.frozen` and the verdict check them on
every pull request; these round trips check the writers themselves. They run in the
scheduled suite `writers` (`tests/nix_scheduled_suites.json`), nightly and on pushes to
`main`, so the CI time of pull requests does not grow with each new writer.
"""

from pathlib import Path
from types import ModuleType

import pytest

from conformance import (after_error_evidence, authored_after_error, algorithm_evidence, alias_evidence,
                         authored_algorithms, authored_aliases, authored_clock, authored_counters, counter_evidence,
                         authored_checks, authored_collations, authored_date_functions, authored_date_modifiers,
                         authored_default_writes, authored_generated,
                         authored_deletes, authored_fromless, authored_indexes, authored_joins, authored_json,
                         authored_json_each,
                         authored_json_functions, authored_keys, authored_merged, authored_numbers,
                         authored_obligations, authored_queries, authored_right, authored_row_writes,
                         authored_upserts, authored_using, authored_without_rowid, authored_writes, check_evidence,
                         clock_evidence, collation_evidence, date_function_evidence, generated_evidence,
                         date_modifier_evidence, default_write_evidence, delete_evidence, fromless_evidence,
                         index_evidence,
                         join_evidence, json_each_evidence, json_evidence, json_function_evidence, key_evidence,
                         merged_evidence, number_evidence, obligation_evidence, query_evidence, right_evidence,
                         row_write_evidence, upsert_evidence, using_evidence, without_rowid_evidence, write_evidence,
                         authored_strict, strict_evidence, authored_drops, drop_evidence,
                         authored_text_functions, text_function_evidence, authored_numeric_functions,
                         numeric_function_evidence, authored_json_edits, json_edit_evidence, authored_jsonb,
                         jsonb_evidence, authored_aggregates, aggregate_evidence,
                         authored_printf, printf_evidence, authored_subqueries, subquery_evidence,
                         authored_expression_forms, expression_form_evidence, authored_distinct_having,
                         distinct_having_evidence, authored_foreign_keys, foreign_key_evidence,
                         authored_triggers, trigger_evidence, authored_possible_results, possible_result_evidence,
                         authored_parameters, parameter_evidence, authored_compound, compound_evidence,
                         authored_pragmas, pragma_evidence)
from conformance.authored_resolution import definitions as resolution_definitions
from conformance.corpus import load

pytestmark = [pytest.mark.integration, pytest.mark.conformance,
              pytest.mark.requires_native("translation-program", "sqlite3")]


@pytest.mark.parametrize(("evidence", "cases", "version"), [(query_evidence, authored_queries, 7),
                                                            (number_evidence, authored_numbers, 8),
                                                            (write_evidence, authored_writes, 9),
                                                            (obligation_evidence, authored_obligations, 10),
                                                            (row_write_evidence, authored_row_writes, 11),
                                                            (delete_evidence, authored_deletes, 12),
                                                            (join_evidence, authored_joins, 13),
                                                            (using_evidence, authored_using, 14),
                                                            (right_evidence, authored_right, 15),
                                                            (merged_evidence, authored_merged, 16),
                                                            (key_evidence, authored_keys, 17),
                                                            (alias_evidence, authored_aliases, 18),
                                                            (upsert_evidence, authored_upserts, 19),
                                                            (algorithm_evidence, authored_algorithms, 20),
                                                            (fromless_evidence, authored_fromless, 21),
                                                            (json_evidence, authored_json, 22),
                                                            (json_function_evidence, authored_json_functions, 23),
                                                            (json_each_evidence, authored_json_each, 24),
                                                            (default_write_evidence, authored_default_writes, 25),
                                                            (clock_evidence, authored_clock, 26),
                                                            (date_function_evidence, authored_date_functions, 27),
                                                            (date_modifier_evidence, authored_date_modifiers, 28),
                                                            (index_evidence, authored_indexes, 29),
                                                            (without_rowid_evidence, authored_without_rowid, 30),
                                                            (collation_evidence, authored_collations, 31),
                                                            (check_evidence, authored_checks, 32),
                                                            (generated_evidence, authored_generated, 33),
                                                            (strict_evidence, authored_strict, 34),
                                                            (drop_evidence, authored_drops, 35),
                                                            (text_function_evidence, authored_text_functions, 36),
                                                            (numeric_function_evidence, authored_numeric_functions,
                                                             37),
                                                            (json_edit_evidence, authored_json_edits, 38),
                                                            (jsonb_evidence, authored_jsonb, 39),
                                                            (aggregate_evidence, authored_aggregates, 40),
                                                            (printf_evidence, authored_printf, 41),
                                                            (subquery_evidence, authored_subqueries, 42),
                                                            (expression_form_evidence, authored_expression_forms, 43),
                                                            (distinct_having_evidence, authored_distinct_having, 44),
                                                            (foreign_key_evidence, authored_foreign_keys, 45),
                                                            (trigger_evidence, authored_triggers, 46),
                                                            (possible_result_evidence, authored_possible_results, 47),
                                                            (parameter_evidence, authored_parameters, 48),
                                                            (compound_evidence, authored_compound, 49),
                                                            (pragma_evidence, authored_pragmas, 50)],
                         ids=["queries", "numbers", "writes", "obligations", "row-writes", "deletes", "joins", "using",
                              "right", "merged", "keys", "aliases", "upserts", "algorithms", "fromless", "json",
                              "json-functions", "json-each", "default-writes", "clock",
                              "date-functions", "date-modifiers", "indexes", "without-rowid",
                              "collations", "checks", "generated", "strict", "drops",
                              "text-functions", "numeric-functions", "json-edits", "jsonb", "aggregates", "printf",
                              "subqueries", "expression-forms", "distinct-having", "foreign-keys", "triggers", "possible-results",
                              "parameters", "compound", "pragmas"])
def test_coverage_corpus_round_trips(evidence: ModuleType, cases: ModuleType, version: int, tmp_path: Path) -> None:
    """The corpus writer records the cases of its case module and writes a corpus of version 5
    records that reads back unchanged and replays natively, and refuses to replace an existing
    directory."""
    assert evidence.CORPUS.records is cases.records
    manifest = evidence.publish(tmp_path / "corpus")
    assert manifest["nativeVersion"] == 5 and manifest["corpusVersion"] == version
    assert manifest["recordedCases"] == len(cases.definitions())
    assert load(tmp_path / "corpus")[0] == manifest
    with pytest.raises(ValueError, match="already exists"):
        evidence.publish(tmp_path / "corpus")


def test_after_error_corpus_round_trips(tmp_path: Path) -> None:
    """`conformance.after_error_evidence.publish` writes corpus version 51 of version 6 records,
    which run on after an error, that reads back unchanged and replays natively in that mode,
    and refuses to replace an existing directory."""
    assert after_error_evidence.CORPUS.records is authored_after_error.records
    manifest = after_error_evidence.publish(tmp_path / "corpus")
    assert manifest["nativeVersion"] == 6 and manifest["corpusVersion"] == 51
    assert manifest["recordedCases"] == len(authored_after_error.definitions())
    assert load(tmp_path / "corpus")[0] == manifest
    with pytest.raises(ValueError, match="already exists"):
        after_error_evidence.publish(tmp_path / "corpus")


def test_counters_corpus_round_trips(tmp_path: Path) -> None:
    """`conformance.counter_evidence.publish` writes corpus version 52 of version 7 records, which
    run on after an error and hold the connection counters, that reads back unchanged and replays
    natively with the counters, and refuses to replace an existing directory."""
    assert counter_evidence.CORPUS.records is authored_counters.records
    manifest = counter_evidence.publish(tmp_path / "corpus")
    assert manifest["nativeVersion"] == 7 and manifest["corpusVersion"] == 52
    assert manifest["recordedCases"] == len(authored_counters.definitions())
    assert load(tmp_path / "corpus")[0] == manifest
    with pytest.raises(ValueError, match="already exists"):
        counter_evidence.publish(tmp_path / "corpus")


def test_resolution_corpus_round_trips(tmp_path: Path) -> None:
    """`conformance.resolution_evidence.publish` writes a corpus of version 5 records that reads
    back unchanged and replays natively, and refuses to replace an existing directory."""
    from conformance.resolution_evidence import publish
    manifest = publish(tmp_path / "corpus")
    assert manifest["nativeVersion"] == 5 and manifest["corpusVersion"] == 6
    assert manifest["recordedCases"] == len(resolution_definitions())
    assert load(tmp_path / "corpus")[0] == manifest
    with pytest.raises(ValueError, match="already exists"):
        publish(tmp_path / "corpus")
