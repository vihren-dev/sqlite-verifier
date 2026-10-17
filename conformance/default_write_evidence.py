"""Publish the authored coverage cases of literal defaults with the writes of ADR 0012 as a
new corpus (slice 6e1).

`python -m conformance.default_write_evidence --output DIRECTORY` records the cases of
`conformance.authored_default_writes` natively as version 5 records with outputs and
writes them as corpus version 25 through `conformance.authored_evidence`.
"""

from pathlib import Path

from conformance import authored_evidence
from conformance.authored_default_writes import records
from conformance.case_format import Json

CORPUS = authored_evidence.AuthoredCorpus(
    records=records, definitions=Path(__file__).with_name("authored_default_writes.py"),
    source_name="authored-default-writes", part="default-writes", corpus_version=25,
    evidence_kind="default-write-coverage")
"""The coverage corpus of defaults with writes: version 25, after the coverage corpus of
`json_each`."""


def publish(directory: Path) -> dict[str, Json]:
    """Acquire, store, load and freshly replay a new coverage corpus of defaults with writes."""
    return authored_evidence.publish(CORPUS, directory)


if __name__ == "__main__":
    authored_evidence.main(CORPUS, "Record the authored cases of literal defaults with writes natively and write "
                                   "them as a new corpus directory.")
