"""The layer rules of the surface and the text package below it (ADR 0016, D2, amended), read
from the import lines of every Lean package and from the Nix build.

1. Nothing below the surface imports it: no Lean file of another package under `packages/`
   imports a module of `packages/belay`, and no other lakefile requires it.
2. Nothing below the text package imports it: no Lean file of a package other than the surface
   and the text package imports a module of `packages/belay-sqlite-text`, and no lakefile other
   than the surface's requires it.
3. The surface imports only its own modules, the text package's, the model's roots (the roots of
   the libraries in the model's `lakefile.toml`), `Init`, `Std` and `Lean`; the text package
   imports only its own modules, the model's roots and Lean's libraries.
4. The conformance runtime contains the text package's program but not the surface: in
   `build-support/`, only the surface's own derivation and the `surface` test suite name the
   surface, and the runtime's derivation names the text package.
5. The translation program does not import the model's umbrella root, even indirectly,
   so its syntax translation does not depend on that root's proof and example imports.
"""

from pathlib import Path
import re
import tomllib

import pytest

pytestmark = pytest.mark.unit

ROOT = Path(__file__).resolve().parents[1]
PACKAGES = ROOT / "packages"
SURFACE = PACKAGES / "belay"
TEXT = PACKAGES / "belay-sqlite-text"
MODEL_ROOTS = {root for library in tomllib.loads((PACKAGES / "belay-sqlite-model/lakefile.toml").read_text())["lean_lib"]
               for root in library["roots"] or [library["name"]]}
"""The model's root modules, the only model modules that the surface and the text package may
import: the roots of each library of the model, or its name for a library that lists its modules
by globs."""
EXTERNAL_ROOTS = {"Init", "Std", "Lean"}
"""The Lean libraries that the surface and the text package may import."""
SURFACE_NAMES = re.compile(r"surfacePackage|sources\.surface|packages/belay\b(?!-)")
"""The ways that a Nix file names the surface package."""


def lean_files(package: Path) -> list[Path]:
    """The Lean files of a package, without Lake's build folder."""
    return [path for path in package.rglob("*.lean") if ".lake" not in path.relative_to(package).parts]


def module_name(package: Path, path: Path) -> str:
    """The module that a Lean file of a package defines."""
    return ".".join(path.relative_to(package).with_suffix("").parts)


def imports(path: Path) -> list[str]:
    """The modules that a Lean file imports, from its `import` lines."""
    return [name for line in re.findall(r"(?m)^import (.+)$", path.read_text()) for name in line.split()]


def modules(package: Path) -> set[str]:
    """The modules of a package, without its lakefile."""
    return {module_name(package, path) for path in lean_files(package) if path.name != "lakefile.lean"}


def import_closure(entrypoint: str, dependencies: dict[str, list[str]]) -> set[str]:
    """Find every transitive import of an entrypoint, including external leaf modules."""
    pending = [entrypoint]
    visited: set[str] = set()
    while pending:
        name = pending.pop()
        if name not in visited:
            visited.add(name)
            pending.extend(dependencies.get(name, []))
    return visited


def test_translation_program_avoids_the_model_umbrella() -> None:
    """Rule 5: follow imports through local modules and public model roots to detect
    indirect dependencies on the model umbrella, which brings proofs into translation."""
    dependencies = {module_name(package, path): imports(path)
                    for package in (TEXT, PACKAGES / "belay-sqlite-model")
                    for path in lean_files(package) if path.name != "lakefile.lean"}
    assert "TranslationProgram" in dependencies
    assert "Belay.Sqlite.Model" not in import_closure("TranslationProgram", dependencies)


@pytest.mark.parametrize("indirect", [False, True], ids=["direct", "through-codec"])
def test_import_closure_finds_a_reintroduced_model_umbrella(indirect: bool) -> None:
    """The layer check's traversal must detect an umbrella import hidden behind a
    public codec root, as well as one added directly to the translation program."""
    umbrella, codec = "Belay.Sqlite.Model", "Belay.Sqlite.Model.Codec"
    dependencies = {"TranslationProgram": [codec if indirect else umbrella], codec: [umbrella]}
    assert umbrella in import_closure("TranslationProgram", dependencies)


def test_the_surface_and_the_text_package_have_modules() -> None:
    """The rules below read the packages' files and the model's roots; an empty set would make
    them pass vacuously."""
    assert {"Belay", "Belay.Sqlite"} <= modules(SURFACE)
    assert {"Belay.Sqlite.Parse", "Belay.Sqlite.Translation"} <= modules(TEXT)
    assert {"Belay.Sqlite.Model", "Belay.Sqlite.Model.Codec", "Belay.Sqlite.Model.Codec.SyntaxJson"} <= MODEL_ROOTS


@pytest.mark.parametrize("upper", [SURFACE, TEXT], ids=["surface", "text"])
def test_no_lower_package_imports_or_requires_an_upper_one(upper: Path) -> None:
    """Rules 1 and 2: no Lean file or lakefile of a package below `upper` names it; the packages
    below the text package are all but the surface and the text package."""
    names = modules(upper)
    allowed = {SURFACE, upper}
    pattern = re.compile(r"\.\./" + re.escape(upper.name) + r"(?![-\w])")
    found = []
    for package in sorted(path for path in PACKAGES.iterdir() if path.is_dir() and path not in allowed):
        found += [f"{path.relative_to(ROOT)}: {name}" for path in lean_files(package)
                  for name in imports(path) if name in names]
        found += [str(path.relative_to(ROOT)) for path in package.glob("lakefile.*") if pattern.search(path.read_text())]
    assert found == []


@pytest.mark.parametrize("package", [SURFACE, TEXT], ids=["surface", "text"])
def test_imports_are_own_modules_model_roots_and_lean(package: Path) -> None:
    """Rule 3: every import of a surface file is its own module, a text package module, a model
    root or a Lean library; every import of a text package file is its own module, a model root or a
    Lean library."""
    allowed = modules(package) | (modules(TEXT) if package == SURFACE else set())
    found = [f"{path.relative_to(ROOT)}: {name}" for path in lean_files(package) if path.name != "lakefile.lean"
             for name in imports(path)
             if name not in allowed and name not in MODEL_ROOTS and name.split(".")[0] not in EXTERNAL_ROOTS]
    assert found == []


SURFACE_SUITE = "tests.nix"
"""The Nix file of the test suites, whose `surface` suite builds its runtime root from the
surface package; any line of it may name the surface."""
SURFACE_BUILD_LINES = frozenset({
    "sources.nix: surface = let folder = root + /packages/belay; in fs.toSource {",
    "default.nix: surfacePackage = leanPackage {",
    'default.nix: directory = "packages/belay";',
    "default.nix: source = sources.surface;",
    "default.nix: inherit leanPackages surfacePackage textPackage;",
})
"""The other lines of `build-support/` that may name the surface: its sources, its derivation,
and the argument that passes it to the test suites."""


def test_only_the_surface_build_and_its_suite_name_the_surface() -> None:
    """Rule 4: in `build-support/`, only the lines of `SURFACE_BUILD_LINES` and the test suites'
    file name the surface, so the conformance runtime does not contain it; the runtime's
    derivation copies the text package's program."""
    lines = [f"{path.name}: {line.strip()}" for path in sorted((ROOT / "build-support").glob("*.nix"))
             for line in path.read_text().splitlines() if SURFACE_NAMES.search(line)]
    assert [line for line in lines if not line.startswith(SURFACE_SUITE + ": ") and line not in SURFACE_BUILD_LINES] == []
    assert "default.nix: surfacePackage = leanPackage {" in lines
    runtime = (ROOT / "build-support/default.nix").read_text().split("conformanceRuntime = ", 1)[1].split("'';", 1)[0]
    assert "${textPackage}/.lake/build/bin/belay-sqlite-translate" in runtime
