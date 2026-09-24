"""Keep proof failure distinct from unsupported semantics and invalid inputs."""

from typing import Literal

Status = Literal["VERIFIED", "VIOLATED", "UNVERIFIED", "UNSUPPORTED", "INPUT_ERROR"]


class Rejection(Exception):
    """A user-facing, non-success result with optional UTF-8 SQL source coordinates."""

    def __init__(self, status: Status, message: str, *, source: str = "",
                 start: int = 0, end: int = 0) -> None:
        super().__init__(message)
        self.status = status
        self.source = source
        self.start = start
        self.end = end

    def diagnostic(self) -> dict[str, str | int]:
        """Expose stable machine-readable coordinates without claiming a counterexample."""
        return {"status": self.status, "message": str(self), "source": self.source,
                "start": self.start, "end": self.end}
