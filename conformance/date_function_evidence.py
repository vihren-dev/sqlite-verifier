"""Publish the authored coverage cases of the date and time functions of ADR 0012 as a new
corpus (slice 6f).

`python -m conformance.date_function_evidence --output DIRECTORY` records the cases of
`conformance.authored_date_functions` natively under the controlled clock as version 5
records with outputs and writes them as corpus version 27 through
`conformance.authored_evidence`.
"""

from pathlib import Path

from conformance import authored_evidence
from conformance.authored_date_functions import records
from conformance.case_format import Json

CORPUS = authored_evidence.AuthoredCorpus(
    records=records, definitions=Path(__file__).with_name("authored_date_functions.py"),
    source_name="authored-date-functions", part="date-functions", corpus_version=27,
    evidence_kind="date-function-coverage")
"""The coverage corpus of the date and time functions: version 27, after the coverage corpus
of the clock."""


def publish(directory: Path) -> dict[str, Json]:
    """Acquire, store, load and freshly replay a new coverage corpus of the date and time
    functions."""
    return authored_evidence.publish(CORPUS, directory)


if __name__ == "__main__":
    authored_evidence.main(CORPUS, "Record the authored cases of the date and time functions natively under the "
                                   "controlled clock and write them as a new corpus directory.")
