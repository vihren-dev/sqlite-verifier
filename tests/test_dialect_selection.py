"""Profiles select a parser grammar through `belay/sqlite/dialects.py`, with no fallback.

The selection takes the library metadata, the release, the SQLite source id and the
compile options of a profile. These tests use small metadata documents; the binding
tests check the selection against the built library.
"""

import pytest

from belay.sqlite.dialects import (
    NoParserForDialect, ProfileIdentity, check_supported_profiles, options_in_effect, select_grammar)
from belay.sqlite.profiles import SOURCE_IDS, SUPPORTED_PROFILES

pytestmark = [pytest.mark.unit, pytest.mark.parser]
METADATA: dict[str, object] = {
    "api": 1,
    "releases": [{"version": "3.51.0", "sourceId": SOURCE_IDS["3.51.0"],
                  "grammarOptions": ["SQLITE_ENABLE_UPDATE_DELETE_LIMIT", "SQLITE_OMIT_TRIGGER"]},
                 {"version": "3.46.0", "sourceId": SOURCE_IDS["3.46.0"], "grammarOptions": []}],
    "dialects": [{"version": "3.51.0", "grammarOptions": [], "grammar": "a" * 64},
                 {"version": "3.51.0", "grammarOptions": ["SQLITE_ENABLE_UPDATE_DELETE_LIMIT"], "grammar": "b" * 64},
                 {"version": "3.46.0", "grammarOptions": [], "grammar": "c" * 64}],
    "grammars": [],
}
"""Two releases; 3.51.0 has a default dialect and one with UPDATE ... LIMIT."""
RELEASE = ProfileIdentity("3.51.0", SOURCE_IDS["3.51.0"])
"""The default build of 3.51.0."""


def test_current_profiles_select_their_default_dialects() -> None:
    """Each supported profile selects its release's dialect without grammar options."""
    assert select_grammar(METADATA, RELEASE) == "a" * 64
    assert select_grammar(METADATA, ProfileIdentity("3.46.0", SOURCE_IDS["3.46.0"])) == "c" * 64
    assert [profile.engine for profile in SUPPORTED_PROFILES] == ["3.51.0", "3.46.0"]
    check_supported_profiles(METADATA)


def test_only_grammar_options_select_the_dialect() -> None:
    """Compile options that are not grammar options, and option values, change nothing."""
    options = ("THREADSAFE=1", "MAX_COLUMN=2000", "ENABLE_UPDATE_DELETE_LIMIT")
    assert options_in_effect(options, ["SQLITE_ENABLE_UPDATE_DELETE_LIMIT"]) == ("SQLITE_ENABLE_UPDATE_DELETE_LIMIT",)
    assert select_grammar(METADATA, ProfileIdentity("3.51.0", SOURCE_IDS["3.51.0"], options[:2])) == "a" * 64
    assert select_grammar(METADATA, ProfileIdentity("3.51.0", SOURCE_IDS["3.51.0"], options)) == "b" * 64


@pytest.mark.parametrize("profile,message", [
    (ProfileIdentity("3.45.0", "x"), "has no SQLite 3.45.0"),
    (ProfileIdentity("3.51.0", "2025-01-01 other"), "another build"),
    (ProfileIdentity("3.51.0", SOURCE_IDS["3.51.0"], ("OMIT_TRIGGER",)), r"\['SQLITE_OMIT_TRIGGER'\]"),
])
def test_profiles_without_a_built_dialect_are_refused(profile: ProfileIdentity, message: str) -> None:
    """An unknown release, another source id, or options without a dialect select no grammar."""
    with pytest.raises(NoParserForDialect, match=message) as error:
        select_grammar(METADATA, profile)
    assert error.value.status == "UNSUPPORTED" and str(error.value).startswith("No parser for this dialect")
    assert str(error.value).endswith("Select a supported profile, or install a verifier whose parser "
                                     "library has this dialect")


def test_missing_supported_dialect_fails_the_check() -> None:
    """A library without a dialect for a supported profile fails the load check."""
    without = {**METADATA, "dialects": [METADATA["dialects"][0]]}  # type: ignore[index]
    with pytest.raises(NoParserForDialect, match="3.46.0"):
        check_supported_profiles(without)
