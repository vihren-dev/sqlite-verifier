"""Publish the authored coverage cases of `json_each` in FROM as a new corpus (ADR 0012,
amendment 5, slice 6d).

`python -m conformance.json_each_evidence --output DIRECTORY` records the cases of
`conformance.authored_json_each` natively as version 5 records with outputs and writes
them as corpus version 24 through `conformance.authored_evidence`.
"""

from pathlib import Path

from conformance import authored_evidence
from conformance.authored_json_each import records
from conformance.case_format import Json

CORPUS = authored_evidence.AuthoredCorpus(
    records=records, definitions=Path(__file__).with_name("authored_json_each.py"),
    source_name="authored-json-each", part="json-each", corpus_version=24, evidence_kind="json-each-coverage")
"""The coverage corpus of `json_each`: version 24, after the coverage corpus of the further
JSON functions."""


def publish(directory: Path) -> dict[str, Json]:
    """Acquire, store, load and freshly replay a new coverage corpus of `json_each`."""
    return authored_evidence.publish(CORPUS, directory)


if __name__ == "__main__":
    authored_evidence.main(CORPUS, "Record the authored cases of json_each natively and write them as a new "
                                   "corpus directory.")
