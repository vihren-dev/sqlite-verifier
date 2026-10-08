"""Attach nearby upstream requirement comments to original assertion locations."""

import re

from conformance.case_format import Json


def evidence(source: str, line: int) -> list[dict[str, Json]]:
    """Retain the nearest EVIDENCE-OF comment block; ambiguous blocks get no automatic credit."""
    lines = source.splitlines()[:max(0, line - 1)]
    references: list[dict[str, Json]] = []
    for index in reversed(range(len(lines))):
        text = lines[index].strip()
        if references and text and not text.startswith("#"):
            break
        found = re.search(r"EVIDENCE-OF: (R-\d{5}-\d{5})", text)
        if found:
            references.insert(0, {"id": found[1], "line": index + 1})
    return references
