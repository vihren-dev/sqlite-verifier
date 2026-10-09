"""Select the SQL parser of a conformance case from its recorded execution profile.

The parser library holds one grammar for each built dialect. A case of corpora v4 and v5
records its profile: release, SQLite source id and compile options. Cases of corpora v1
to v3 record only the source id; the default native library recorded them, with no
grammar options. A case whose profile has no built dialect is not parsed: its verdict
is `MODEL_UNSUPPORTED`, and the parse with another dialect never replaces it.
"""

from pathlib import Path
import sys

from belay.sqlite.dialects import ProfileIdentity
from belay.sqlite.parser_library import ParserLibrary, installed_library, load
from belay.sqlite.sql_tree import SqlParser
from conformance.case_format import Json
from conformance.execution_profile import recorded_profile
from conformance.native_library import DEFAULT_ENGINE_VERSION, SOURCE_ID

NO_PARSER_REASON = "no parser for this dialect"
"""The reason of a `MODEL_UNSUPPORTED` case whose recorded profile has no built dialect."""
DEFAULT_NATIVE_PROFILE = ProfileIdentity(DEFAULT_ENGINE_VERSION, SOURCE_ID)
"""The default native library, which records fixtures, generated programs and corpora v1 to v3."""


def runtime_library(runtime: Path) -> ParserLibrary:
    """Load the parser library of a conformance runtime root."""
    return load(installed_library(runtime.resolve(), sys.platform))


def default_parser(runtime: Path) -> SqlParser:
    """Return the parser of the default native library's dialect."""
    return SqlParser.for_profile(runtime_library(runtime), DEFAULT_NATIVE_PROFILE)


def record_profile(record: dict[str, Json]) -> ProfileIdentity:
    """Return the profile that a native record was recorded with."""
    if record.get("nativeVersion") == 4:
        profile = recorded_profile(record)
        return ProfileIdentity(profile.engine_version, profile.source_id, profile.compile_options)
    source_id = record.get("sourceId")
    if not isinstance(source_id, str):
        raise ValueError("Native record has no source id")
    return ProfileIdentity(DEFAULT_ENGINE_VERSION, source_id)


def record_parser(library: ParserLibrary, record: dict[str, Json]) -> SqlParser:
    """Return the parser of the record's dialect; refuse a record without a built dialect."""
    return SqlParser.for_profile(library, record_profile(record))
