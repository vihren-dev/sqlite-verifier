"""The production root imports no engineering examples or demonstrations (ADR 0006)."""

from pathlib import Path
import re
import tomllib

import pytest

ROOT = Path(__file__).resolve().parents[1]
MODEL_ROOT = ROOT / "packages/belay-sqlite"
PRODUCTION_ROOT_MODULE = "SqliteVerifier"
"""The public application root that every proof check imports as its trusted base."""
EXAMPLES_LIBRARY = "EngineeringExamples"
"""The Lake library that holds demonstrations and example proofs as test code."""
pytestmark = [pytest.mark.unit]


def example_modules() -> set[str]:
    """Read the example module names from the Lake configuration that builds them."""
    configuration = tomllib.loads((ROOT / "lakefile.toml").read_text())
    libraries = {library["name"]: library for library in configuration["lean_lib"]}
    return set(libraries[EXAMPLES_LIBRARY]["globs"])


def local_source(module: str) -> Path | None:
    """Find a project module's source in the application or model package."""
    relative = Path(*module.split(".")).with_suffix(".lean")
    for base in (ROOT, MODEL_ROOT):
        if (base / relative).is_file():
            return base / relative
    return None


def production_closure() -> set[str]:
    """Follow source imports from the production root through project modules only."""
    pending, reached = [PRODUCTION_ROOT_MODULE], set()
    while pending:
        module = pending.pop()
        source = local_source(module)
        if module in reached or source is None:
            continue
        reached.add(module)
        for line in re.findall(r"(?m)^import (.+)$", source.read_text()):
            pending.extend(line.split())
    return reached


def test_production_root_excludes_example_modules() -> None:
    """A restored example import in the root or a production module fails this check."""
    examples = example_modules()
    assert examples, f"{EXAMPLES_LIBRARY} lists no modules in lakefile.toml"
    reached = production_closure()
    assert PRODUCTION_ROOT_MODULE in reached
    assert not reached & examples, f"Production imports reach example modules: {sorted(reached & examples)}"
