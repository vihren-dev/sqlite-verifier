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

from conformance import (algorithm_evidence, alias_evidence, authored_algorithms, authored_aliases,
                         authored_deletes, authored_fromless, authored_joins, authored_json,
                         authored_json_functions, authored_keys, authored_merged, authored_numbers,
                         authored_obligations, authored_queries, authored_right, authored_row_writes,
                         authored_upserts, authored_using, authored_writes, delete_evidence, fromless_evidence,
                         join_evidence, json_evidence, json_function_evidence, key_evidence, merged_evidence,
                         number_evidence, obligation_evidence, query_evidence, right_evidence, row_write_evidence,
                         upsert_evidence, using_evidence, write_evidence)
from conformance.authored_resolution import definitions as resolution_definitions
from conformance.corpus import load

pytestmark = [pytest.mark.integration, pytest.mark.conformance,
              pytest.mark.requires_native("parser-library", "sqlite3")]


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
                                                            (json_function_evidence, authored_json_functions, 23)],
                         ids=["queries", "numbers", "writes", "obligations", "row-writes", "deletes", "joins", "using",
                              "right", "merged", "keys", "aliases", "upserts", "algorithms", "fromless", "json",
                              "json-functions"])
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
