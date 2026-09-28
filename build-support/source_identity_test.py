"""Check component invalidation, including added/deleted inputs and ignored docs."""

import json
from pathlib import Path
import shutil
import subprocess
from tempfile import TemporaryDirectory

ROOT = Path(__file__).resolve().parents[1]


def identities(root: Path) -> dict[str, str]:
    """Evaluate only fileset store identities through the single locked package set."""
    expression = f'''let pkgs = import {ROOT}/build-support/locked-nixpkgs.nix {{}};
      sources = import {ROOT}/build-support/sources.nix {{ inherit (pkgs) lib;
      root = /. + {json.dumps(str(root))}; }};
      in builtins.mapAttrs (_: source: toString source) sources'''
    result = subprocess.run(["nix", "eval", "--impure", "--json",
        "--extra-experimental-features", "nix-command flakes", "--expr", expression],
        capture_output=True, text=True, timeout=60)
    if result.returncode:
        raise RuntimeError(result.stderr)
    return json.loads(result.stdout)


def main() -> None:
    """Test complete selected membership without copying builds or checkout metadata."""
    with TemporaryDirectory(prefix="sqlite-nix-identities-") as temporary:
        root = Path(temporary)
        for directory in ("parser", "SqliteVerifier", "migration_check", "examples", "packaging", "docs",
                          "tests", "tools", "conformance", "build-support"):
            shutil.copytree(ROOT / directory, root / directory,
                            ignore=shutil.ignore_patterns("__pycache__"))
        for path in [*ROOT.glob("*.lean"), *(ROOT / name for name in
                     ("lakefile.toml", "lake-manifest.json", "lean-toolchain", "LICENSE", "pytest.ini", "conftest.py"))]:
            shutil.copy2(path, root / path.name)
        baseline = identities(root)
        (root / "README.md").write_text("unrelated documentation")
        assert identities(root) == baseline, "documentation invalidated builds"
        for directory in ("parser", "SqliteVerifier", "examples"):
            for ignored in (".git", ".jj", ".lake", "build", "dist", "__pycache__"):
                path = root / directory / ignored
                path.mkdir(exist_ok=True)
                (path / "generated.lean").write_text("ignored")
                (path / "generated.py").write_text("ignored")
        assert identities(root) == baseline, "generated trees invalidated builds"
        for relative, affected in (("parser/new_generator.py", {"parsers", "unit"}),
                                   ("SqliteVerifier/NewModule.lean", {"lean"}),
                                   ("NewRoot.lean", {"lean"}),
                                   ("migration_check/new_module.py", {"runtime", "unit"}),
                                   ("tests/test_added.py", {"unit"})):
            path = root / relative
            path.write_text("new input")
            added = identities(root)
            for component in baseline:
                assert (added[component] != baseline[component]) == (component in affected), relative
            path.write_text("changed input")
            changed = identities(root)
            assert all(changed[key] != added[key] for key in affected), relative
            renamed = path.with_name("Renamed" + path.name)
            path.rename(renamed)
            renamed_ids = identities(root)
            assert all(renamed_ids[key] != changed[key] for key in affected), relative
            renamed.unlink()
            assert identities(root) == baseline, relative
        for relative, component in (("parser/generate.py", "parsers"),
                                    ("SqliteVerifier/Model.lean", "lean"),
                                    ("migration_check/runtime.py", "runtime")):
            path = root / relative
            content = path.read_bytes()
            path.unlink()
            assert identities(root)[component] != baseline[component], relative
            path.write_bytes(content)
            assert identities(root) == baseline, relative
    print("Fileset identities: edits, additions, deletions, renames and docs passed")


if __name__ == "__main__":
    main()
