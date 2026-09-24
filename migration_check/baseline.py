"""Compare approved source closures to a separately protected, human-reviewed baseline."""

import json
from pathlib import Path
import re
from collections.abc import Mapping

from .diagnostics import Rejection


def check_baseline(path: Path, hashes: Mapping[str, str]) -> None:
    """Reject added, removed, or changed approved dependencies; never update approval implicitly."""
    saved: object = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(saved, dict):
        raise Rejection("INPUT_ERROR", "Approved baseline must be a JSON object of source hashes")
    expected: dict[str, str] = {}
    for name, digest in saved.items():
        if name.startswith("approved/"):
            if not isinstance(digest, str) or re.fullmatch(r"[0-9a-f]{64}", digest) is None:
                raise Rejection("INPUT_ERROR", f"Invalid approved baseline hash: {name}")
            expected[name] = digest
    if not {"approved/Requirements.lean", "approved/Interpretation.lean"} <= expected.keys():
        raise Rejection("INPUT_ERROR", "Baseline must identify Requirements and Interpretation sources")
    actual = {name: digest for name, digest in hashes.items() if name.startswith("approved/")}
    changed = sorted(name for name in expected.keys() | actual.keys() if expected.get(name) != actual.get(name))
    if changed:
        raise Rejection("INPUT_ERROR", "Protected approved sources changed: " + ", ".join(changed))
