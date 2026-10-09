"""Resolve only selected runtime prerequisites during setup, never during discovery."""

from __future__ import annotations

from collections.abc import Callable
import os
from pathlib import Path
import shutil
import sys
from typing import TYPE_CHECKING

import pytest

from tests.runtime_support import run_command

if TYPE_CHECKING:
    from belay.sqlite.sql_tree import SqlParser, Tree

PARSER_LIBRARY = "parser-library"
"""The `requires_native` requirement of the runtime's SQLite parser library."""


def runtime_parser_library(runtime_root: Path) -> Path:
    """Return the parser library's path in a runtime root.

    Nix test targets that do not declare the frontend sources load this plugin too, so it
    cannot import `belay.sqlite.parser_library.installed_library`;
    `tests/parser_binding_test.py` checks that both give the same path.
    """
    return runtime_root / "lib" / ("libsqlite-verifier-parser" + (".dylib" if sys.platform == "darwin" else ".so"))


def require_file(path: Path, *, executable: bool = False) -> Path:
    """Fail setup with the missing build artifact rather than silently dropping coverage."""
    if not path.is_file() or (executable and not os.access(path, os.X_OK)):
        pytest.fail(f"Required runtime file is missing or unusable: {path}; build the runtime first")
    return path


@pytest.fixture(scope="session")
def lean_sysroot(runtime_root: Path, pytestconfig: pytest.Config) -> Path:
    """Use the selected bundled toolchain or resolve the pinned source compiler explicitly."""
    bundled = runtime_root / "lean"
    if pytestconfig.getoption("runtime_variant") == "installed" or (bundled / "bin/lean").is_file():
        require_file(bundled / "bin/lean", executable=True)
        return bundled.resolve()
    compiler = shutil.which("lean")
    if compiler is None:
        pytest.fail("Required Lean compiler is missing; enter the pinned shell and run just setup")
    result = run_command([compiler, "--print-prefix"], cwd=runtime_root, timeout=10)
    if result.returncode:
        pytest.fail(f"Cannot resolve Lean toolchain: {result.diagnostic()}")
    root = Path(result.stdout.strip())
    require_file(root / "bin/lean", executable=True)
    return root.resolve()


@pytest.fixture(scope="session")
def lean_libraries(runtime_root: Path) -> tuple[Path, Path]:
    """Require the separately installed application and model roots in trusted precedence order."""
    application = runtime_root / ".lake/build/lib/lean"
    model = runtime_root / "packages/belay-sqlite/.lake/build/lib/lean"
    require_file(application / "SqliteVerifier.olean")
    require_file(model / "Belay/Sqlite.olean")
    return application, model


@pytest.fixture(scope="session")
def proof_checker(runtime_root: Path) -> Path:
    """Require the actual checker executable for cases that consume it."""
    return require_file(runtime_root / ".lake/build/bin/migration-proof-checker", executable=True)


@pytest.fixture(autouse=True)
def selected_prerequisites(request: pytest.FixtureRequest) -> None:
    """Resource markers drive setup errors; pure cases do not request any runtime fixture."""
    lean = request.node.get_closest_marker("requires_lean")
    if lean is not None:
        request.getfixturevalue("lean_sysroot")
        if lean.args != ("compiler",):
            request.getfixturevalue("lean_libraries")
            request.getfixturevalue("proof_checker")
    native = request.node.get_closest_marker("requires_native")
    if native is not None:
        for tool in native.args or (PARSER_LIBRARY,):
            if tool == PARSER_LIBRARY:
                require_file(runtime_parser_library(request.getfixturevalue("runtime_root")))
            elif not isinstance(tool, str) or shutil.which(tool) is None:
                pytest.fail(f"Required native tool is missing: {tool}")
    if request.node.get_closest_marker("requires_nix") is not None and shutil.which("nix") is None:
        pytest.fail("Required Nix command is missing; enter the pinned shell")


def profile_parser(runtime_root: Path, version: str = "3.51.0") -> SqlParser:
    """Return the runtime library's parser for the supported profile of a SQLite release.

    The implementation imports stay inside the function: Nix test targets that do not
    declare the Python sources still load this plugin.
    """
    from belay.sqlite.dialects import ProfileIdentity
    from belay.sqlite.parser_library import installed_library, load
    from belay.sqlite.profiles import profile
    from belay.sqlite.sql_tree import SqlParser

    selected = profile(version)
    library = load(installed_library(runtime_root.resolve(), sys.platform))
    return SqlParser.for_profile(library, ProfileIdentity(selected.engine, selected.source_id))


@pytest.fixture
def sql_parser(runtime_root: Path) -> Callable[..., SqlParser]:
    """Select the runtime library's parser of a supported profile, by SQLite release."""
    return lambda version="3.51.0": profile_parser(runtime_root, version)


@pytest.fixture
def parse_sql(sql_parser: Callable[..., SqlParser]) -> Callable[..., Tree]:
    """Parse SQL with the runtime library's grammar for the requested SQLite release."""
    from belay.sqlite.sql_tree import parse

    def parse_with_selected_grammar(sql: str, version: str = "3.51.0") -> Tree:
        """Parse with the grammar of the release's supported profile."""
        return parse(sql_parser(version), sql.encode(), "fixture.sql")
    return parse_with_selected_grammar
