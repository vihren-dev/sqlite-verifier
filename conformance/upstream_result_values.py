"""Compare untyped Tcl result values without changing independently recorded SQLite cells."""

import math
import re
import struct

from conformance.case_format import Json
from conformance.native_replay import decode_cell


def helper_cells(rows: list[Json], helper: str) -> list[Json]:
    """Project only the values returned by the pinned eval, onecolumn and exists helpers."""
    helper = helper.removeprefix("aux:")
    if helper == "eval-script":
        return []
    if helper == "exists":
        return [{"integer": {"value": int(bool(rows))}}]
    if helper == "onecolumn":
        return [rows[0][0]] if rows and rows[0] else ["null"]
    if helper != "eval":
        raise ValueError("Tcl helper semantics not reproduced")
    return [cell for row in rows for cell in row]


def verified_real_precision(precision: int | None) -> None:
    """Nonzero Tcl precision can erase REAL differences before the execution trace sees them."""
    if type(precision) is not int or precision != 0:
        raise ValueError("Tcl REAL comparison requires captured tcl_precision=0")


def value_text(cell: Json, precision: int | None) -> str:
    """Render diagnostic text; REAL equality below uses bits rather than Python formatting."""
    kind, value = decode_cell(cell)
    if kind == 5:
        return ""
    if kind == 1:
        return str(value)
    if kind in (3, 4):
        # Pinned tclsqlite.c returns BLOBs as Tcl_NewByteArrayObj: each byte is that codepoint.
        return value.decode("utf-8" if kind == 3 else "latin-1")
    verified_real_precision(precision)
    number = struct.unpack(">d", int(value).to_bytes(8, "big"))[0]
    if math.isnan(number):
        raise ValueError("Tcl REAL NaN result is not supported")
    if math.isinf(number):
        return "Inf" if number > 0 else "-Inf"
    return repr(number)


def values_agree(rows: list[Json], expected: list[str], helper: str, precision: int | None) -> bool:
    """Require exact REAL bits from round-trip Tcl output, and exact text/BLOB byte values."""
    cells = helper_cells(rows, helper)
    if len(cells) != len(expected):
        return False
    for cell, text in zip(cells, expected, strict=True):
        kind, value = decode_cell(cell)
        if kind != 2:
            if value_text(cell, precision) != text:
                return False
            continue
        verified_real_precision(precision)
        # Tcl's default double strings have a decimal point, exponent or signed Inf.
        if not re.fullmatch(r"-?(?:(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:e[+-]?[0-9]+)?|Inf)", text):
            return False
        if "." not in text and "e" not in text and not text.endswith("Inf"):
            return False
        number = float(text)
        if not math.isfinite(number) and text not in {"Inf", "-Inf"}:
            return False
        if number == 0.0 and re.search(r"[1-9]", text.split("e")[0]):
            return False  # Tcl's round-trip zero cannot contain an underflowed nonzero mantissa.
        if math.isnan(number) or int.from_bytes(struct.pack(">d", number), "big") != value:
            return False
    return True
