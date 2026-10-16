"""Publish the authored coverage cases of queries without FROM as a new corpus (ADR 0012,
amendment 5, slice 6a).

`python -m conformance.fromless_evidence --output DIRECTORY` records the cases of
`conformance.authored_fromless` natively as version 5 records with outputs and writes
them as corpus version 21 through `conformance.authored_evidence`.
"""

from pathlib import Path

from conformance import authored_evidence
from conformance.authored_fromless import records
from conformance.case_format import Json

CORPUS = authored_evidence.AuthoredCorpus(
    records=records, definitions=Path(__file__).with_name("authored_fromless.py"),
    source_name="authored-fromless", part="fromless", corpus_version=21, evidence_kind="fromless-coverage")
"""The coverage corpus of queries without FROM: version 21, after the coverage corpus of
conflict algorithms."""


def publish(directory: Path) -> dict[str, Json]:
    """Acquire, store, load and freshly replay a new coverage corpus of queries without FROM."""
    return authored_evidence.publish(CORPUS, directory)


if __name__ == "__main__":
    authored_evidence.main(CORPUS, "Record the authored cases of queries without FROM natively and "
                                   "write them as a new corpus directory.")
