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
"""The Nix suites that receive the narrowed frontend inputs; the others receive the application and frontend."""
LOCAL_PACKAGES = ("belay", "conformance", "migration_check", "tests", "tools")
"""Repository packages whose imports are followed; other imports are standard or pinned libraries."""
pytestmark = [pytest.mark.unit]


def imported_modules(path: Path, root: Path = ROOT) -> set[str]:
    """Local modules that one file imports, so that the closure can follow them.

    `from package import name` may import a submodule, so the candidate `package.name`
    is included when it is a module file. Imports inside functions count too, because
    they run when the function runs.
    """
    package = ".".join(path.relative_to(root).parts[:-1])
    names: set[str] = set()
    for node in ast.walk(ast.parse(path.read_text(encoding="utf-8"))):
        if isinstance(node, ast.ImportFrom):
            base = node.module or ""
            if node.level:
                parent = ".".join(package.split(".")[:len(package.split(".")) - node.level + 1])
                base = f"{parent}.{base}" if base else parent
            names.add(base)
            names.update(f"{base}.{alias.name}" for alias in node.names
                         if module_file(f"{base}.{alias.name}", root) is not None)
        elif isinstance(node, ast.Import):
            names.update(alias.name for alias in node.names)
    return {name for name in names if name.split(".")[0] in LOCAL_PACKAGES}


def module_file(name: str, root: Path = ROOT) -> Path | None:
    """The file that defines a local module, which the closure reads next; None for other names."""
    path = root / (name.replace(".", "/") + ".py")
    return path if path.is_file() else None


def import_closure(test_files: list[str], root: Path = ROOT) -> set[str]:
    """Every local module that a suite's tests can import, which its Nix inputs must contain."""
    pending = [name for file in test_files for name in imported_modules(root / file, root)]
    reached: set[str] = set()
    while pending:
        name = pending.pop()
        path = module_file(name, root)
        if name in reached or path is None:
            continue
        reached.add(name)
        pending.extend(imported_modules(path, root))
    return reached


def declared_frontend() -> set[str]:
    """The frontend modules that the conformance suites receive, which the closure must not exceed."""
    return set(json.loads((ROOT / "tests/conformance_frontend.json").read_text(encoding="utf-8")))


def test_declared_frontend_modules_exist() -> None:
    """A stale entry fails here instead of as a Nix evaluation error."""
    missing = {name for name in declared_frontend() if not (ROOT / (name.replace(".", "/") + ".py")).is_file()}
    assert not missing, f"tests/conformance_frontend.json names missing modules: {sorted(missing)}"


def test_closure_follows_submodules_imported_from_a_package(tmp_path: Path) -> None:
    """`from conformance import helper` reaches the frontend modules that helper imports."""
    for name, text in {"tests/example_test.py": "from conformance import helper\n",
                       "conformance/helper.py": "from . import other\n",
                       "conformance/other.py": "from migration_check.secret import value\n",
                       "migration_check/secret.py": "value = 1\n"}.items():
        (tmp_path / name).parent.mkdir(parents=True, exist_ok=True)
        (tmp_path / name).write_text(text, encoding="utf-8")
    assert "migration_check.secret" in import_closure(["tests/example_test.py"], tmp_path)


def test_closure_follows_nested_frontend_relative_imports(tmp_path: Path) -> None:
    """A relative frontend import resolves inside belay.sqlite and exposes application dependencies."""
    for name, text in {"tests/example_test.py": "from belay.sqlite.sql_model import Table\n",
                       "belay/sqlite/sql_model.py": "from . import helper\n",
                       "belay/sqlite/helper.py": "from migration_check.secret import value\n",
                       "migration_check/secret.py": "value = 1\n"}.items():
        (tmp_path / name).parent.mkdir(parents=True, exist_ok=True)
        (tmp_path / name).write_text(text, encoding="utf-8")
    assert "migration_check.secret" in import_closure(["tests/example_test.py"], tmp_path)


@pytest.mark.parametrize("suite", CONFORMANCE_SUITES)
def test_suite_imports_only_declared_frontend_modules(suite: str) -> None:
    """Add a module that a conformance test starts to import to tests/conformance_frontend.json."""
    files = json.loads((ROOT / "tests/nix_suites.json").read_text(encoding="utf-8"))[suite]
    closure = import_closure(files)
    application = {name for name in closure if name.startswith("migration_check.")}
    assert not application, f"Suite {suite} imports application modules: {sorted(application)}"
    used = {name for name in closure if name.startswith("belay.sqlite.")}
    undeclared = used - declared_frontend()
    assert not undeclared, (f"Suite {suite} imports frontend modules that its Nix inputs omit: "
                            f"{sorted(undeclared)}; add them to tests/conformance_frontend.json")
