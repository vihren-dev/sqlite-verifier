"""Resolve only selected runtime prerequisites during setup, never during discovery."""

from __future__ import annotations

from collections.abc import Callable
import os
from pathlib import Path
import shutil
from typing import TYPE_CHECKING

import pytest

from tests.runtime_support import run_command

if TYPE_CHECKING:
    from belay.sqlite.sql_tree import Tree


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
def lean_library(runtime_root: Path) -> Path:
    """Select compiled project modules independently of the checkout's implementation imports."""
    library = runtime_root / ".lake/build/lib/lean"
    require_file(library / "SqliteVerifier.olean")
    return library


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
            request.getfixturevalue("lean_library")
            request.getfixturevalue("proof_checker")
    native = request.node.get_closest_marker("requires_native")
    if native is not None:
        for tool in native.args or ("sqlite-parser", "sqlite-parser-3.46.0"):
            if tool in ("sqlite-parser", "sqlite-parser-3.46.0"):
                root = request.getfixturevalue("runtime_root")
                require_file(root / "build" / tool, executable=True)
            elif not isinstance(tool, str) or shutil.which(tool) is None:
                pytest.fail(f"Required native tool is missing: {tool}")
    if request.node.get_closest_marker("requires_nix") is not None and shutil.which("nix") is None:
        pytest.fail("Required Nix command is missing; enter the pinned shell")


@pytest.fixture
def parse_sql(runtime_root: Path) -> Callable[..., Tree]:
    """Parse SQL with the selected runtime's pinned grammar for the requested SQLite release.

    The implementation import stays inside the fixture: Nix test targets that do not
    declare the Python sources still load this plugin.
    """
    from belay.sqlite.sql_tree import parse

    def parse_with_selected_grammar(sql: str, version: str = "3.51.0") -> Tree:
        """Choose the parser binary matching the release so its profile check passes."""
        binary = "sqlite-parser" if version == "3.51.0" else "sqlite-parser-3.46.0"
        return parse(runtime_root / "build" / binary, sql.encode(), "fixture.sql", version)
    return parse_with_selected_grammar
