"""Repository pytest options and execution-only runtime fixtures."""

from collections.abc import Callable, Mapping, Sequence
import os
from pathlib import Path

import pytest

from tests.runtime_support import CommandResult, copy_mutable_tree, run_command

pytest_plugins = ["tests.runtime_fixtures", "tests.runtime_installation"]


def pytest_addoption(parser: pytest.Parser) -> None:
    """Select the runtime under test; reports come from pytest's own --junitxml."""
    group = parser.getgroup("sqlite-verifier")
    group.addoption("--runtime-root", type=Path, help="Built executable and examples root")
    group.addoption("--runtime-archive", type=Path, help="Archive to install once for installed cases")
    group.addoption("--runtime-variant", choices=("source", "installed"), default="source")


def pytest_configure(config: pytest.Config) -> None:
    """Reject an archive that would be mislabeled as source or mixed with another root."""
    if config.getoption("runtime_archive") is not None:
        if config.getoption("runtime_root") is not None or config.getoption("runtime_variant") != "installed":
            raise pytest.UsageError("--runtime-archive requires --runtime-variant installed and no --runtime-root")


@pytest.fixture(scope="session")
def runtime_root(pytestconfig: pytest.Config, request: pytest.FixtureRequest) -> Path:
    """Resolve the selected artifact root lazily, without checking unrelated prerequisites."""
    if pytestconfig.getoption("runtime_archive") is not None:
        return request.getfixturevalue("installed_runtime")
    root = pytestconfig.getoption("runtime_root") or pytestconfig.rootpath
    if not root.is_dir():
        pytest.fail(f"Runtime directory is missing: {root}; build the selected runtime first")
    return root.resolve()


@pytest.fixture
def example_factory(runtime_root: Path, tmp_path: Path) -> Callable[[str], Path]:
    """Give each requested example an independent mutable copy, preserving all relative paths."""
    def copy_example(name: str) -> Path:
        """Copy only examples under the selected runtime, using a distinct directory each time."""
        source = (runtime_root / "examples" / name).resolve(strict=True)
        if not source.is_relative_to((runtime_root / "examples").resolve(strict=True)):
            raise ValueError(f"Example escapes selected runtime: {name}")
        destination = tmp_path / f"example-{len(list(tmp_path.glob('example-*')))}"
        return copy_mutable_tree(source, destination)
    return copy_example


@pytest.fixture
def runtime_environment(pytestconfig: pytest.Config, tmp_path: Path) -> dict[str, str]:
    """Poison only installed children, leaving the dev pytest interpreter and parent untouched."""
    if pytestconfig.getoption("runtime_variant") == "source":
        return dict(os.environ)
    poison = tmp_path / "ambient imports"
    poison.mkdir()
    (poison / "json.py").write_text('raise RuntimeError("ambient Python imported")\n')
    return {"HOME": str(tmp_path), "LANG": "C.UTF-8", "PATH": "/usr/bin:/bin",
            "PYTHONPATH": str(poison), "LEAN_PATH": str(poison),
            "MIGRATION_CHECK_LEAN_SYSROOT": str(poison)}


@pytest.fixture
def command_runner(runtime_environment: dict[str, str]) -> Callable[..., CommandResult]:
    """Bind the per-case child environment to the bounded runner."""
    def invoke(arguments: Sequence[str], *, cwd: Path, timeout: float,
               environment: Mapping[str, str] | None = None) -> CommandResult:
        """Allow source-internal fixtures to supply explicit Lean paths without changing defaults."""
        return run_command(arguments, cwd=cwd, timeout=timeout,
                           environment=runtime_environment if environment is None else environment)
    return invoke
