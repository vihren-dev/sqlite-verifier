"""The conformance Nix suites declare every frontend module that their tests import.

`build-support/tests.nix` gives the conformance suites only the frontend modules in
`tests/conformance_frontend.json`, so that a change to the verification application
leaves their cached results valid. The Nix sandbox would reject a missing module, but
only after a long build; this check finds it on the host in less than a second.
"""

import ast
import json
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
CONFORMANCE_SUITES = ("model", "frozen", "harness", "sample", "upstream")
LOCAL_PACKAGES = ("conformance", "migration_check", "tests", "tools")
pytestmark = [pytest.mark.unit]


def imported_modules(path: Path) -> set[str]:
    """Every local module named by an import in the file, including imports inside functions."""
    package = path.parent.name
    names: set[str] = set()
    for node in ast.walk(ast.parse(path.read_text(encoding="utf-8"))):
        if isinstance(node, ast.ImportFrom) and node.module:
            names.add(f"{package}.{node.module}" if node.level == 1 else node.module)
        elif isinstance(node, ast.Import):
            names.update(alias.name for alias in node.names)
    return {name for name in names if name.split(".")[0] in LOCAL_PACKAGES}


def module_file(name: str) -> Path | None:
    """The repository file of a local module, or None for a name that is not a module file."""
    path = ROOT / (name.replace(".", "/") + ".py")
    return path if path.is_file() else None


def import_closure(test_files: list[str]) -> set[str]:
    """Local modules reachable from the given test files through imports."""
    pending = [name for file in test_files for name in imported_modules(ROOT / file)]
    reached: set[str] = set()
    while pending:
        name = pending.pop()
        path = module_file(name)
        if name in reached or path is None:
            continue
        reached.add(name)
        pending.extend(imported_modules(path))
    return reached


def declared_frontend() -> set[str]:
    """Frontend module names that the conformance suites receive as Nix inputs."""
    return set(json.loads((ROOT / "tests/conformance_frontend.json").read_text(encoding="utf-8")))


def test_declared_frontend_modules_exist() -> None:
    """A stale entry fails here instead of as a Nix evaluation error."""
    missing = {name for name in declared_frontend() if not (ROOT / f"migration_check/{name}.py").is_file()}
    assert not missing, f"tests/conformance_frontend.json names missing modules: {sorted(missing)}"


@pytest.mark.parametrize("suite", CONFORMANCE_SUITES)
def test_suite_imports_only_declared_frontend_modules(suite: str) -> None:
    """Add a module that a conformance test starts to import to tests/conformance_frontend.json."""
    files = json.loads((ROOT / "tests/nix_suites.json").read_text(encoding="utf-8"))[suite]
    used = {name.split(".", 1)[1] for name in import_closure(files)
            if name.startswith("migration_check.")}
    undeclared = used - declared_frontend()
    assert not undeclared, (f"Suite {suite} imports frontend modules that its Nix inputs omit: "
                            f"{sorted(undeclared)}; add them to tests/conformance_frontend.json")
