"""Publish the authored coverage cases of conflict algorithms as a new corpus (ADR 0012,
amendment 4, slice 5d).

`python -m conformance.algorithm_evidence --output DIRECTORY` records the cases of
`conformance.authored_algorithms` natively as version 5 records with outputs and writes
them as corpus version 20 through `conformance.authored_evidence`.
"""

from pathlib import Path

from conformance import authored_evidence
from conformance.authored_algorithms import records
from conformance.case_format import Json

CORPUS = authored_evidence.AuthoredCorpus(
    records=records, definitions=Path(__file__).with_name("authored_algorithms.py"),
    source_name="authored-algorithms", part="algorithms", corpus_version=20, evidence_kind="algorithm-coverage")
"""The coverage corpus of conflict algorithms: version 20, after the coverage corpus of
UPSERT."""


def publish(directory: Path) -> dict[str, Json]:
    """Acquire, store, load and freshly replay a new coverage corpus of conflict algorithms."""
    return authored_evidence.publish(CORPUS, directory)


if __name__ == "__main__":
    authored_evidence.main(CORPUS, "Record the authored cases of conflict algorithms natively and "
                                   "write them as a new corpus directory.")
