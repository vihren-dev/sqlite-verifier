"""The dialect table: which dialects the parser library builds, and their grammar identities.

A dialect is a release with the grammar options in effect. Its grammar identity is a
SHA-256 digest of the inputs that decide its syntax and tokens. `parser/dialects.json`
records each built dialect with its identity, and the build fails when the sources give
another identity. Two dialects share a parser only when their identities are equal.
"""

from dataclasses import dataclass
import hashlib
import json
from pathlib import Path

from parser.grammar_sources import ReleaseSources

TABLE_FIELDS = frozenset({"releases", "dialects"})
"""The fields of the dialect table object."""
RELEASE_FIELDS = frozenset({"version", "sources"})
"""The fields of a release entry: its version label and its source directory under `parser/`."""
DIALECT_FIELDS = frozenset({"version", "grammarOptions", "grammar"})
"""The fields of a dialect entry: its release, the grammar options in effect and its identity."""
IDENTITY_FORMAT = "sqlite-verifier-grammar-1"
"""Names the digest layout below; a new layout must change it, so no old identity matches."""


@dataclass(frozen=True)
class Release:
    """A release that the library builds, and its vendored source directory under `parser/`."""

    version: str
    sources: str


@dataclass(frozen=True)
class Dialect:
    """A built dialect and the grammar identity that the dialect table records for it."""

    version: str
    grammar_options: tuple[str, ...]
    grammar: str


@dataclass(frozen=True)
class DialectTable:
    """The checked-in dialect table: the releases to read and the dialects to build."""

    releases: tuple[Release, ...]
    dialects: tuple[Dialect, ...]


def grammar_identity(preprocessed: str, release: ReleaseSources, options: tuple[str, ...]) -> str:
    """Digest the generated grammar file, the tokenizer sources and the options in effect.

    `preprocessed` is Lemon's `-E` output of `parse.y` for these options. It contains no
    path, so the same sources in another directory give the same identity.
    """
    inputs = {"format": IDENTITY_FORMAT, "grammar": preprocessed, "tokenizer": release.tokenizer,
              "characterTables": release.character_tables, "grammarOptions": sorted(options)}
    encoded = json.dumps(inputs, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
    return hashlib.sha256(encoded.encode()).hexdigest()


def _strings(value: object, where: str) -> tuple[str, ...]:
    """Return a list of strings from the table, or fail with its location."""
    if not isinstance(value, list) or not all(isinstance(item, str) for item in value):
        raise ValueError(f"{where} must be a list of strings in parser/dialects.json")
    return tuple(value)


def _text(entry: dict[str, object], key: str, where: str) -> str:
    """Return a non-empty string field of a table entry, or fail with its location."""
    value = entry.get(key)
    if not isinstance(value, str) or not value:
        raise ValueError(f"{where} needs a non-empty string {key!r} in parser/dialects.json")
    return value


def _entries(table: dict[str, object], key: str, fields: frozenset[str]) -> list[dict[str, object]]:
    """Return the entries of one table list, each with exactly the given fields."""
    entries = table.get(key)
    if not isinstance(entries, list) or not entries or not all(
            isinstance(entry, dict) and set(entry) == fields for entry in entries):
        raise ValueError(f"{key!r} in parser/dialects.json must be a non-empty list of objects "
                         f"with the fields {sorted(fields)}")
    return entries


def load_table(path: Path) -> DialectTable:
    """Read and validate the dialect table at path."""
    table = json.loads(path.read_text())
    if not isinstance(table, dict) or set(table) != TABLE_FIELDS:
        raise ValueError(f"{path} must be an object with 'releases' and 'dialects'")
    releases = tuple(Release(_text(entry, "version", "A release"), _text(entry, "sources", "A release"))
                     for entry in _entries(table, "releases", RELEASE_FIELDS))
    dialects = tuple(Dialect(_text(entry, "version", "A dialect"),
                             _strings(entry["grammarOptions"], "grammarOptions"),
                             _text(entry, "grammar", "A dialect"))
                     for entry in _entries(table, "dialects", DIALECT_FIELDS))
    if len({release.version for release in releases}) != len(releases):
        raise ValueError(f"{path} names a release twice")
    if len({(dialect.version, frozenset(dialect.grammar_options)) for dialect in dialects}) != len(dialects):
        raise ValueError(f"{path} names a dialect twice")
    return DialectTable(releases, dialects)


def check_release(release: Release, sources: ReleaseSources) -> None:
    """Fail when the table's version label differs from the version in the release's sqlite3.h."""
    if release.version != sources.version:
        raise ValueError(f"parser/{release.sources} contains SQLite {sources.version}, but "
                         f"parser/dialects.json labels it {release.version}. Correct the release "
                         "entry, or point it at the source directory of that release.")


def check_dialect(dialect: Dialect, release: ReleaseSources, identity: str) -> None:
    """Fail unless the dialect's options are grammar options of its release, the build can
    make the dialect, and the sources give the identity that the table records."""
    unknown = sorted(set(dialect.grammar_options) - set(release.grammar_options))
    if unknown:
        raise ValueError(f"Dialect {dialect.version} names options that are not grammar options "
                         f"of the release: {unknown}")
    if dialect.grammar_options:
        raise ValueError(f"Dialect {dialect.version} {list(dialect.grammar_options)} has grammar "
                         "options; the build makes only default dialects")
    if identity != dialect.grammar:
        raise ValueError(f"The sources of dialect {dialect.version} {list(dialect.grammar_options)} "
                         f"give grammar identity {identity}, but parser/dialects.json records "
                         f"{dialect.grammar}. Check the source change, then record the new identity.")
