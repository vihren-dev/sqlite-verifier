"""Publish the authored coverage cases of pragmas as statements as a new corpus (ADR 0019,
slice 2).

`python -m conformance.pragma_evidence --output DIRECTORY` records the cases of
`conformance.authored_pragmas` natively as version 5 records with outputs and writes them as
corpus version 50 through `conformance.authored_evidence`.
"""

from pathlib import Path

from conformance import authored_evidence
from conformance.authored_pragmas import records
from conformance.case_format import Json

CORPUS = authored_evidence.AuthoredCorpus(
    records=records, definitions=Path(__file__).with_name("authored_pragmas.py"),
    source_name="authored-pragmas", part="pragmas", corpus_version=50,
    evidence_kind="pragma-coverage")
"""The coverage corpus of pragmas: version 50."""


def publish(directory: Path) -> dict[str, Json]:
    """Acquire, store, load and freshly replay a new coverage corpus of pragmas."""
    return authored_evidence.publish(CORPUS, directory)


if __name__ == "__main__":
    authored_evidence.main(CORPUS, "Record the authored cases of pragmas natively and write them as a new "
                                   "corpus directory.")
