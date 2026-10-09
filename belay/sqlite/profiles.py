"""Select fixed SQLite semantics without application catalogs or implicit SQL operations."""

from dataclasses import dataclass
import re
from typing import Literal

from .errors import SqlError


@dataclass(frozen=True)
class ExecutionProfile:
    """An exact supported engine version under its documented SQLite-only settings."""

    engine: Literal["3.51.0", "3.46.0"] = "3.51.0"

    @property
    def source_id(self) -> str:
        """Return the `sqlite_source_id()` of the pinned build of this release."""
        return SOURCE_IDS[self.engine]

    @property
    def wire_tag(self) -> str:
        """Return the structural version tag shared by all model record consumers."""
        return {"3.51.0": "sqlite351", "3.46.0": "sqlite346"}[self.engine]


SOURCE_IDS = {
    "3.51.0": "2025-11-04 19:38:17 fb2c931ae597f8d00a37574ff67aeed3eced4e5547f9120744ae4bfa8e74527b",
    "3.46.0": "2024-05-23 13:25:27 96c92aba00c8375bc32fafcdf12429c58bd8aabfcadab6683e35bbb9cdebf19e",
}
"""The SQLite source id of each supported release; a profile with another build selects no parser."""

#: The default profile selects the current modeled engine without extra SQL operations.
DEFAULT_PROFILE = ExecutionProfile()

SUPPORTED_PROFILES = (DEFAULT_PROFILE, ExecutionProfile("3.46.0"))
"""The profiles that the verifier supports. This list is a product decision: a dialect in the
parser library does not add a profile here, and each profile here needs a dialect there."""


def profile(specification: str) -> ExecutionProfile:
    """Only version strings select semantics; JSON files never inject framework policy."""
    if re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", specification) is None:
        raise SqlError("INPUT_ERROR", "Profile must be an exact SQLite version string: 3.51.0 or 3.46.0")
    for supported in SUPPORTED_PROFILES:
        if supported.engine == specification:
            return supported
    raise SqlError("UNSUPPORTED", f"Requested SQLite {specification}; supported versions: 3.51.0, 3.46.0")
