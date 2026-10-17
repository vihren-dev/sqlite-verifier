"""Publish the authored coverage cases of the date and time modifiers of ADR 0012 as a new
corpus (slice 6g).

`python -m conformance.date_modifier_evidence --output DIRECTORY` records the cases of
`conformance.authored_date_modifiers` natively under the controlled clock as version 5
records with outputs and writes them as corpus version 28 through
`conformance.authored_evidence`.
"""

from pathlib import Path

from conformance import authored_evidence
from conformance.authored_date_modifiers import records
from conformance.case_format import Json

CORPUS = authored_evidence.AuthoredCorpus(
    records=records, definitions=Path(__file__).with_name("authored_date_modifiers.py"),
    source_name="authored-date-modifiers", part="date-modifiers", corpus_version=28,
    evidence_kind="date-modifier-coverage")
"""The coverage corpus of the date and time modifiers: version 28, after the coverage corpus
of the date and time functions."""


def publish(directory: Path) -> dict[str, Json]:
    """Acquire, store, load and freshly replay a new coverage corpus of the date and time
    modifiers."""
    return authored_evidence.publish(CORPUS, directory)


if __name__ == "__main__":
    authored_evidence.main(CORPUS, "Record the authored cases of the date and time modifiers natively under the "
                                   "controlled clock and write them as a new corpus directory.")
