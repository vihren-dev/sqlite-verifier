"""Select the parser library's grammar for an execution profile.

A dialect is a SQLite release with the grammar options in effect; the library's metadata
lists each built dialect with its grammar identity. A profile names a release, the
SQLite source id of its build and the compile options that `PRAGMA compile_options`
reports. The selection never falls back to another dialect: a profile without a built
dialect has no parser.
"""

from dataclasses import dataclass

from .errors import SqlError
from .profiles import SUPPORTED_PROFILES

Metadata = dict[str, object]
"""The decoded metadata document of the parser library."""


@dataclass(frozen=True)
class ProfileIdentity:
    """The parts of an execution profile that decide its syntax."""

    version: str
    source_id: str
    compile_options: tuple[str, ...] = ()


class NoParserForDialect(SqlError):
    """The parser library has no dialect for the profile; the profile's SQL is not parsed."""

    def __init__(self, message: str) -> None:
        """Report the profile as unsupported, with the reason in the message."""
        super().__init__("UNSUPPORTED", f"No parser for this dialect: {message}")


def _entries(metadata: Metadata, key: str) -> list[dict[str, object]]:
    """Return one list of the metadata, which the binding read from the library."""
    entries = metadata.get(key)
    if not isinstance(entries, list) or not all(isinstance(entry, dict) for entry in entries):
        raise ValueError(f"The parser library metadata has no valid {key!r} list")
    return entries


def options_in_effect(compile_options: tuple[str, ...], grammar_options: list[str]) -> tuple[str, ...]:
    """Return the grammar options among the compile options, as macro names.

    `PRAGMA compile_options` reports `SQLITE_OMIT_TRIGGER` as `OMIT_TRIGGER`, and a value
    after `=`. The grammar's conditionals test only whether a macro is defined, so the
    selection compares names without values.
    """
    names = {"SQLITE_" + option.split("=", 1)[0] for option in compile_options}
    return tuple(sorted(names & set(grammar_options)))


def select_grammar(metadata: Metadata, profile: ProfileIdentity) -> str:
    """Return the grammar identity of the profile's dialect, or refuse the profile."""
    releases = {release["version"]: release for release in _entries(metadata, "releases")}
    dialects = _entries(metadata, "dialects")
    built = ", ".join(f"{dialect['version']} {dialect['grammarOptions']}" for dialect in dialects)
    release = releases.get(profile.version)
    if release is None:
        raise NoParserForDialect(f"the parser library has no SQLite {profile.version}; it has {built}")
    if release["sourceId"] != profile.source_id:
        raise NoParserForDialect(f"SQLite {profile.version} with source id {profile.source_id!r} is "
                                 f"another build than the parser's {release['sourceId']!r}")
    grammar_options = release["grammarOptions"]
    if not isinstance(grammar_options, list):
        raise ValueError("The parser library metadata has invalid grammar options")
    options = options_in_effect(profile.compile_options, grammar_options)
    for dialect in dialects:
        if dialect["version"] == profile.version and tuple(sorted(dialect["grammarOptions"])) == options:
            return str(dialect["grammar"])
    raise NoParserForDialect(f"SQLite {profile.version} with grammar options {list(options)}; "
                             f"the parser library has {built}")


def check_supported_profiles(metadata: Metadata) -> None:
    """Fail unless each supported profile of the verifier resolves to a built dialect."""
    for profile in SUPPORTED_PROFILES:
        select_grammar(metadata, ProfileIdentity(profile.engine, profile.source_id))
