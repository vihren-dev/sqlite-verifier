"""Publish the authored coverage cases of JSON reading and `json_extract` as a new corpus
(ADR 0012, amendment 5, slice 6b).

`python -m conformance.json_evidence --output DIRECTORY` records the cases of
`conformance.authored_json` natively as version 5 records with outputs and writes them as
corpus version 22 through `conformance.authored_evidence`.
"""

from pathlib import Path

from conformance import authored_evidence
from conformance.authored_json import records
from conformance.case_format import Json

CORPUS = authored_evidence.AuthoredCorpus(
    records=records, definitions=Path(__file__).with_name("authored_json.py"),
    source_name="authored-json", part="json", corpus_version=22, evidence_kind="json-coverage")
"""The coverage corpus of JSON reading and `json_extract`: version 22, after the coverage
corpus of queries without FROM."""


def publish(directory: Path) -> dict[str, Json]:
    """Acquire, store, load and freshly replay a new coverage corpus of JSON reading."""
    return authored_evidence.publish(CORPUS, directory)


if __name__ == "__main__":
    authored_evidence.main(CORPUS, "Record the authored cases of JSON reading and json_extract natively "
                                   "and write them as a new corpus directory.")
