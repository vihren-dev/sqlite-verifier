"""Publish the authored cases of the statements after an error as a new corpus (task "Evidence
for the statements after an error").

`python -m conformance.after_error_evidence --output DIRECTORY` records the cases of
`conformance.authored_after_error` natively as version 6 records, which run on after an error,
and writes them as corpus version 51 through `conformance.authored_evidence`.
"""

from pathlib import Path

from conformance import authored_evidence
from conformance.authored_after_error import records
from conformance.case_format import Json

CORPUS = authored_evidence.AuthoredCorpus(
    records=records, definitions=Path(__file__).with_name("authored_after_error.py"),
    source_name="authored-after-error", part="after-error", corpus_version=51,
    evidence_kind="after-error-coverage", native_version=6)
"""The coverage corpus of the statements after an error: version 51, after the corpus of
pragmas (version 50)."""


def publish(directory: Path) -> dict[str, Json]:
    """Acquire, store, load and freshly replay a new coverage corpus of the statements after an
    error."""
    return authored_evidence.publish(CORPUS, directory)


if __name__ == "__main__":
    authored_evidence.main(CORPUS, "Record the authored cases of the statements after an error natively and write "
                                   "them as a new corpus directory.")
