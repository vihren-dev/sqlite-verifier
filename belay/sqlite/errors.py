"""Report SQL refusal or parser failure with stable UTF-8 source coordinates."""

from typing import Literal

SqlStatus = Literal["UNVERIFIED", "UNSUPPORTED", "INPUT_ERROR"]


class SqlError(Exception):
    """A user-facing, non-success result with optional UTF-8 SQL source coordinates."""

    def __init__(self, status: SqlStatus, message: str, *, source: str = "",
                 start: int = 0, end: int = 0) -> None:
        super().__init__(message)
        self.status = status
        self.source = source
        self.start = start
        self.end = end

    def diagnostic(self) -> dict[str, str | int]:
        """Expose the refusal classification, message and exact SQL coordinates."""
        return {"status": self.status, "message": str(self), "source": self.source,
                "start": self.start, "end": self.end}
