"""Read the sources of one vendored SQLite release that decide its syntax and tokens.

The parser library names each grammar by a digest of these sources (see
`parser/dialect_table.py`). This module finds them in the release directory: the
version and source id in `sqlite3.h`, the tokenizer and keyword code and the character
tables in `sqlite3.c`, and the macros that `parse.y` and the tokenizer test. These macros
are the release's grammar options; the build extracts them, so nobody keeps a list.
"""

from dataclasses import dataclass
import hashlib
import json
from pathlib import Path
import re

TOKENIZER_START = re.compile(r"^/\*+ Begin file tokenize\.c \*+/$", re.M)
"""The amalgamation marker where `tokenize.c`, which includes `keywordhash.h`, starts."""
TOKENIZER_END = re.compile(r"^SQLITE_PRIVATE int sqlite3RunParser\(", re.M)
"""The first function of `tokenize.c` that the parser does not use: it runs SQLite's own parser."""
TABLES_START = re.compile(r"^SQLITE_PRIVATE const unsigned char sqlite3UpperToLower\[\] = \{$", re.M)
"""The case-folding table of `global.c`, which the tokenizer reads for keywords."""
TABLES_LAST = re.compile(r"^SQLITE_PRIVATE const unsigned char sqlite3CtypeMap\[256\] = \{$", re.M)
"""The character-class table of `global.c`; the tables end at the close of this array."""
LEMON_CONDITIONAL = re.compile(r"^[ \t]*%(?:ifdef|ifndef|if)\b(.*)$", re.M)
"""A Lemon conditional in `parse.y`: it adds or removes grammar rules."""
C_CONDITIONAL = re.compile(r"^[ \t]*#[ \t]*(?:ifdef|ifndef|if|elif)\b(.*)$", re.M)
"""A C conditional in the tokenizer sources: it changes how text becomes tokens."""
DEFINEDNESS = re.compile(r"[A-Za-z_]\w*|defined|[\s()!|&]")
"""The only parts of a conditional that test whether a macro is defined, not its value."""


@dataclass(frozen=True)
class ReleaseSources:
    """The syntax-deciding sources of one release, read from its vendored directory."""

    version: str
    source_id: str
    tokenizer: str
    character_tables: str
    grammar_options: tuple[str, ...]


def section(text: str, start: re.Pattern[str], end: re.Pattern[str], where: str) -> str:
    """Return text from the start marker up to the end marker, or fail if one is missing."""
    first = start.search(text)
    last = end.search(text, first.end()) if first else None
    if first is None or last is None:
        raise ValueError(f"Cannot find the {where} in sqlite3.c; check the vendored release")
    return text[first.start():last.start()]


def character_tables(text: str) -> str:
    """Return the case-folding and character-class tables of `global.c`."""
    first = TABLES_START.search(text)
    last = TABLES_LAST.search(text, first.end()) if first else None
    close = re.compile(r"^\};$", re.M).search(text, last.end()) if last else None
    if first is None or close is None:
        raise ValueError("Cannot find the character tables in sqlite3.c; check the vendored release")
    return text[first.start():close.end()]


def conditional_macros(text: str, conditional: re.Pattern[str]) -> set[str]:
    """Return the macros that the conditionals test; fail for a test of a macro value."""
    joined = text.replace("\\\n", " ")
    macros: set[str] = set()
    for match in conditional.finditer(joined):
        expression = re.sub(r"/\*.*?\*/|//.*", "", match.group(1))
        if "".join(DEFINEDNESS.findall(expression)) != expression:
            raise ValueError(f"Conditional tests a macro value, which grammar options do not "
                             f"describe yet: {match.group(0).strip()}")
        macros |= set(re.findall(r"[A-Za-z_]\w*", expression)) - {"defined"}
    return macros


def header_define(header: str, name: str) -> str:
    """Return the string value of a `#define` in `sqlite3.h`."""
    match = re.search(rf'^#define {name}\s+"([^"]+)"$', header, re.M)
    if match is None:
        raise ValueError(f"sqlite3.h has no {name}; check the vendored release")
    return match.group(1)


def check_hashes(directory: Path) -> None:
    """Fail unless each file named in `sha256.json` has its recorded digest."""
    expected = json.loads((directory / "sha256.json").read_text())
    for name, digest in sorted(expected.items()):
        if hashlib.sha256((directory / name).read_bytes()).hexdigest() != digest:
            raise ValueError(f"{directory / name} differs from its digest in sha256.json; "
                             "restore the unmodified upstream file")


def read_release(directory: Path) -> ReleaseSources:
    """Read a hash-checked release directory with `parse.y`, `sqlite3.c` and `sqlite3.h`."""
    check_hashes(directory)
    amalgamation = (directory / "sqlite3.c").read_text()
    header = (directory / "sqlite3.h").read_text()
    tokenizer = section(amalgamation, TOKENIZER_START, TOKENIZER_END, "tokenizer")
    tables = character_tables(amalgamation)
    options = (conditional_macros((directory / "parse.y").read_text(), LEMON_CONDITIONAL)
               | conditional_macros(tokenizer, C_CONDITIONAL) | conditional_macros(tables, C_CONDITIONAL))
    return ReleaseSources(header_define(header, "SQLITE_VERSION"),
                          header_define(header, "SQLITE_SOURCE_ID"),
                          tokenizer, tables, tuple(sorted(options)))
