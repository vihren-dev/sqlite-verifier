"""Independent stored-value expectations for the real-runner witness SQL."""
from __future__ import annotations

from dataclasses import dataclass
import struct
from typing import Literal


@dataclass(frozen=True)
class Cell:
    """A SQLite stored class and exact payload, after declared affinity conversion."""

    kind: Literal["null", "integer", "real", "text", "blob"]
    value: int | bytes | None = None

    def lean(self) -> str:
        """Render independent expectations using inert stored-value constructors."""
        if self.kind == "null":
            return ".null"
        if self.kind in ("integer", "real"):
            return f"(.{self.kind} ({self.value}))"
        assert isinstance(self.value, bytes)
        return f".{self.kind} [" + ",".join(map(str, self.value)) + "]"

    def observation(self) -> list[str]:
        """Match native typeof/quote/hex observations, retaining bytes after embedded NUL."""
        if self.kind == "null":
            return ["null", "NULL", ""]
        if self.kind == "blob":
            assert isinstance(self.value, bytes)
            hex_value = self.value.hex().upper()
            return ["blob", f"X'{hex_value}'", hex_value]
        if self.kind == "text":
            assert isinstance(self.value, bytes)
            text = self.value.decode().split("\0", 1)[0].replace("'", "''")
            return ["text", f"'{text}'", self.value.hex().upper()]
        if self.kind == "real":
            assert isinstance(self.value, int)
            value = struct.unpack(">d", self.value.to_bytes(8, "big"))[0]
            text = str(value)
        else:
            text = str(self.value)
        return [self.kind, text, text.encode().hex().upper()]


def text(value: str) -> Cell:
    """Preserve UTF-8 bytes, including embedded NUL."""
    return Cell("text", value.encode())


NULL = Cell("null")
ROWS: tuple[tuple[int, tuple[Cell, ...]], ...] = (
    (-(2**63), (NULL, Cell("integer", 1), text("not-an-integer"), Cell("blob", b"\0\xff"),
               text("same"), text("/a"), text("session"), text("host"), NULL, NULL, NULL)),
    (-1, (NULL, Cell("integer", 2), Cell("real", 0x3FF4000000000000), Cell("integer", 0),
          text("same"), text("/a"), text("session"), text("host"), text("unparsed"),
          Cell("blob", b"\x80\xff"), text("a\0b"))),
    (2**63-1, (text(""), Cell("blob", b"\x01\x02"), Cell("integer", -2), Cell("integer", 0),
              Cell("blob", b"\0\xff"), text("123"), text("456"), text("789"), NULL,
              text("author"), text("intent"))),
)
COUNTS = (0, 1, 3)
OLD_COLUMNS = ("id", "timestamp", "duration", "exit", "command", "cwd", "session", "hostname",
               "deleted_at", "author", "intent")


def native_rows(count: int) -> list[list[int | str]]:
    """Expected rows originate in this fixture, never in native or modeled execution."""
    return [[rowid, *(part for cell in cells for part in cell.observation())]
            for rowid, cells in ROWS[:count]]


def lean_rows(count: int, *, after: bool = False) -> str:
    """Expected ADD results explicitly contain one trailing NULL for every old row."""
    rows = []
    for rowid, cells in ROWS[:count]:
        values = (*cells, NULL) if after else cells
        rows.append(f"{{ rowid := ({rowid}), values := [" +
                    ",".join(cell.lean() for cell in values) + "] }")
    return "[" + ",".join(rows) + "]"
