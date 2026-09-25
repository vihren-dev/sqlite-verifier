"""Select fixed SQLite semantics without application catalogs or implicit SQL operations."""

from dataclasses import dataclass
import re
from typing import Literal

from .diagnostics import Rejection


@dataclass(frozen=True)
class ExecutionProfile:
    """An exact supported engine version under its documented SQLite-only settings."""

    engine: Literal["3.51.0", "3.46.0"] = "3.51.0"

    def lean(self) -> str:
        """Seal the selected version independently of candidate proof aliases."""
        return {"3.51.0": ".sqlite351", "3.46.0": ".sqlite346"}[self.engine]


LEGACY_PROFILE = ExecutionProfile()


def profile(specification: str) -> ExecutionProfile:
    """Only version strings select semantics; JSON files never inject framework policy."""
    if re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", specification) is None:
        raise Rejection("INPUT_ERROR", "Profile must be an exact SQLite version string: 3.51.0 or 3.46.0")
    if specification == "3.51.0":
        return LEGACY_PROFILE
    if specification == "3.46.0":
        return ExecutionProfile("3.46.0")
    raise Rejection("UNSUPPORTED", f"Requested SQLite {specification}; supported versions: 3.51.0, 3.46.0")
