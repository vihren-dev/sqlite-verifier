"""Write the generated C inputs of the parser library: its grammar list and its metadata.

`library.c` includes both files. The metadata document describes the library to its
callers: the API version, each release with its source id and grammar options, each
built dialect with its grammar identity, and each grammar with its size.
"""

from dataclasses import dataclass
import json
from pathlib import Path
import re

from parser.dialect_table import Dialect

API_VERSION = 1
"""The API version of `parser/library.h`; callers refuse a library with another version."""
JsonValue = str | int | list["JsonValue"] | dict[str, "JsonValue"]
"""The JSON values that the metadata document contains."""


@dataclass(frozen=True)
class ReleaseRecord:
    """What the metadata says about one release; each release derivation writes one."""

    version: str
    source_id: str
    grammar_options: tuple[str, ...]


@dataclass(frozen=True)
class Grammar:
    """One parser of the library: its identity, its Lemon prefix and its size."""

    identity: str
    prefix: str
    productions: int
    tokens: int


def grammar_size(syntax_c: str, syntax_h: str) -> tuple[int, int]:
    """Return the production count of Lemon's parser tables and the number of terminals."""
    rules = re.search(r"^#define YYNRULE\s+(\d+)$", syntax_c, re.M)
    if rules is None:
        raise ValueError("The generated parser has no YYNRULE; check the Lemon output")
    return int(rules.group(1)), len(re.findall(r"^#define P_\w+\s+\d+$", syntax_h, re.M))


def metadata(releases: list[ReleaseRecord], dialects: list[Dialect],
             grammars: list[Grammar]) -> dict[str, JsonValue]:
    """Return the metadata document of a library with these releases, dialects and grammars."""
    return {
        "api": API_VERSION,
        "releases": [{"version": release.version, "sourceId": release.source_id,
                      "grammarOptions": list(release.grammar_options)} for release in releases],
        "dialects": [{"version": dialect.version, "grammarOptions": list(dialect.grammar_options),
                      "grammar": dialect.grammar} for dialect in dialects],
        "grammars": [{"grammar": grammar.identity, "productions": grammar.productions,
                      "tokens": grammar.tokens} for grammar in grammars],
    }


def c_string(text: str) -> str:
    """Return a C string literal with exactly the bytes of the ASCII text."""
    if not text.isascii():
        raise ValueError("The metadata document must be ASCII")
    return '"' + text.replace("\\", "\\\\").replace('"', '\\"') + '"'


def write_sources(directory: Path, document: dict[str, JsonValue], grammars: list[Grammar]) -> None:
    """Write `library_grammars.inc` and `library_metadata.inc` into directory."""
    lines = [f'GRAMMAR({grammar.prefix}, "{grammar.identity}")' for grammar in grammars]
    (directory / "library_grammars.inc").write_text("\n".join(lines) + "\n")
    text = json.dumps(document, separators=(",", ":"))
    (directory / "library_metadata.inc").write_text(c_string(text) + "\n")
