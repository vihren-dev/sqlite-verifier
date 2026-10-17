"""Publish the authored coverage cases of the clock of ADR 0012 as a new corpus (slice 6e2).

`python -m conformance.clock_evidence --output DIRECTORY` records the cases of
`conformance.authored_clock` natively under the controlled clock as version 5 records with
outputs and writes them as corpus version 26 through `conformance.authored_evidence`.
"""

from pathlib import Path

from conformance import authored_evidence
from conformance.authored_clock import records
from conformance.case_format import Json

CORPUS = authored_evidence.AuthoredCorpus(
    records=records, definitions=Path(__file__).with_name("authored_clock.py"),
    source_name="authored-clock", part="clock", corpus_version=26, evidence_kind="clock-coverage")
"""The coverage corpus of the clock: version 26, after the coverage corpus of defaults with
writes."""


def publish(directory: Path) -> dict[str, Json]:
    """Acquire, store, load and freshly replay a new coverage corpus of the clock."""
    return authored_evidence.publish(CORPUS, directory)


if __name__ == "__main__":
    authored_evidence.main(CORPUS, "Record the authored cases of the clock natively under the controlled clock and "
                                   "write them as a new corpus directory.")
