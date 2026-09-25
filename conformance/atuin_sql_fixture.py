"""Independent stored-value expectations for ordinary SQLite SQL fixtures."""
from __future__ import annotations

from dataclasses import dataclass
import struct
from typing import Literal


@dataclass(frozen=True)
class Cell:
    """A SQLite stored class and exact payload, after declared affinity conversion."""

    kind: Literal["null", "integer", "real", "text", "blob"]
    value: int | bytes | None = None

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


HISTORY_INSERT = """INSERT INTO history(rowid,id,timestamp,duration,exit,command,cwd,session,hostname,deleted_at,author,intent) VALUES
(-9223372036854775808,NULL,1,'not-an-integer',X'00FF','same','/a','session','host',NULL,NULL,NULL),
(-1,NULL,2,1.25,0,'same','/a','session','host','unparsed',X'80FF',CAST(X'610062' AS TEXT)),
(9223372036854775807,'',X'0102',-2,0,X'00FF',123,456,789,NULL,'author','intent');"""


def history_seed(count: int) -> str:
    """Insert deliberately chosen independent fixture values, then select its prefix."""
    if count == 0:
        return ""
    suffix = "" if count == 3 else "DELETE FROM history WHERE rowid != -9223372036854775808;"
    return HISTORY_INSERT + "\n" + suffix
