"""The `ctypes` binding in `belay/sqlite/parser_library.py` calls the built parser library.

These tests load the library of the runtime root and check the binding's behavior: the
metadata check, the result of an unknown grammar, the documents of each status, and
calls from several threads.
"""

from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import sys

import pytest

from belay.sqlite.dialects import ProfileIdentity, select_grammar
from belay.sqlite.parser_library import ParserLibrary, ParserLibraryError, check_metadata, installed_library, load
from belay.sqlite.profiles import SUPPORTED_PROFILES
from tests.parser_inputs import OVERSIZED, RAISE_EXPRESSION

pytestmark = [pytest.mark.integration, pytest.mark.parser, pytest.mark.requires_native]


@pytest.fixture(scope="module")
def library(runtime_root: Path) -> ParserLibrary:
    """The runtime's library, loaded once for these tests."""
    return load(installed_library(runtime_root.resolve(), sys.platform))


def grammar(library: ParserLibrary, version: str) -> str:
    """Return the grammar identity of the supported profile of a release."""
    profile = next(profile for profile in SUPPORTED_PROFILES if profile.engine == version)
    return select_grammar(library.metadata, ProfileIdentity(profile.engine, profile.source_id))


def test_load_returns_one_library_per_path(library: ParserLibrary) -> None:
    """A second load of the same path gives the loaded library, and a missing path fails clearly."""
    assert load(library.path) is library
    with pytest.raises(ParserLibraryError, match="missing"):
        load(library.path.with_name("absent.so"))


def test_metadata_check_refuses_another_api_or_a_missing_profile(library: ParserLibrary) -> None:
    """A library with another API version, or without a supported profile's dialect, is refused."""
    with pytest.raises(ParserLibraryError, match="has API 2"):
        check_metadata({**library.metadata, "api": 2}, library.path)  # type: ignore[dict-item]
    with pytest.raises(ParserLibraryError, match="cannot parse a supported profile"):
        check_metadata({**library.metadata, "dialects": []}, library.path)  # type: ignore[dict-item]


def test_each_release_parses_with_its_own_grammar(library: ParserLibrary) -> None:
    """The documents name the requested grammar; the RAISE case separates the two releases."""
    for version, status in (("3.51.0", "PARSED"), ("3.46.0", "INPUT_ERROR")):
        document = library.parse(grammar(library, version), RAISE_EXPRESSION)
        assert isinstance(document, dict) and document["status"] == status
        if status == "PARSED":
            assert document["grammar"] == grammar(library, version)


def test_unknown_grammar_and_limits(library: ParserLibrary) -> None:
    """An unknown identity raises; oversized and invalid input give their statuses."""
    with pytest.raises(ParserLibraryError, match="no such grammar") as error:
        library.parse("0" * 64, b"SELECT 1;")
    assert str(library.path) in str(error.value) and "reinstall the verifier" in str(error.value)
    identity = grammar(library, "3.51.0")
    assert library.parse(identity, OVERSIZED) == {"status": "RESOURCE_LIMIT", "offset": 0}
    assert library.parse(identity, b"SELECT '\xff';") == {"status": "INPUT_ERROR", "offset": 0}


def test_calls_from_several_threads_give_the_serial_results(library: ParserLibrary) -> None:
    """The binding's lock keeps parallel callers from running the library concurrently."""
    identity = grammar(library, "3.51.0")
    texts = [f"SELECT {index}, 'x{index}';".encode() for index in range(200)]
    serial = [library.parse(identity, text) for text in texts]
    with ThreadPoolExecutor(8) as pool:
        assert list(pool.map(lambda text: library.parse(identity, text), texts)) == serial
