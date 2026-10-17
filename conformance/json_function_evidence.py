"""Publish the authored coverage cases of `json_type`, `json_valid`, `json_array_length`
and `json` as a new corpus (ADR 0012, amendment 5, slice 6c).

`python -m conformance.json_function_evidence --output DIRECTORY` records the cases of
`conformance.authored_json_functions` natively as version 5 records with outputs and
writes them as corpus version 23 through `conformance.authored_evidence`.
"""

from pathlib import Path

from conformance import authored_evidence
from conformance.authored_json_functions import records
from conformance.case_format import Json

CORPUS = authored_evidence.AuthoredCorpus(
    records=records, definitions=Path(__file__).with_name("authored_json_functions.py"),
    source_name="authored-json-functions", part="json-functions", corpus_version=23,
    evidence_kind="json-function-coverage")
"""The coverage corpus of the further JSON functions: version 23, after the coverage corpus
of JSON reading."""


def publish(directory: Path) -> dict[str, Json]:
    """Acquire, store, load and freshly replay a new coverage corpus of the further JSON functions."""
    return authored_evidence.publish(CORPUS, directory)


if __name__ == "__main__":
    authored_evidence.main(CORPUS, "Record the authored cases of json_type, json_valid, json_array_length "
                                   "and json natively and write them as a new corpus directory.")
