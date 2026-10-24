"""Publish the authored cases of the connection counters as a new corpus (ADR 0024, slice 1).

`python -m conformance.counter_evidence --output DIRECTORY` records the cases of
`conformance.authored_counters` natively as version 7 records, which run on after an error and
hold the counters of the writer connection, and writes them as corpus version 52 through
`conformance.authored_evidence`.
"""

from pathlib import Path

from conformance import authored_evidence
from conformance.authored_counters import records
from conformance.case_format import Json

CORPUS = authored_evidence.AuthoredCorpus(
    records=records, definitions=Path(__file__).with_name("authored_counters.py"),
    source_name="authored-counters", part="counters", corpus_version=52,
    evidence_kind="counter-coverage", native_version=7)
"""The coverage corpus of the connection counters: version 52, after the corpus of the statements
after an error (version 51)."""


def publish(directory: Path) -> dict[str, Json]:
    """Acquire, store, load and freshly replay a new coverage corpus of the connection counters."""
    return authored_evidence.publish(CORPUS, directory)


if __name__ == "__main__":
    authored_evidence.main(CORPUS, "Record the authored cases of the connection counters natively and write "
                                   "them as a new corpus directory.")
