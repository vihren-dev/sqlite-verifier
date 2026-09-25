"""Record exact loader dependencies for source-tree runs without altering the shared Lean installation."""

from pathlib import Path

from runtime_dependencies import native_dependencies, run

ROOT = Path(__file__).resolve().parents[1]


def main() -> None:
    """Run after trusted executables build; Nix's elan may patch the Linux ELF interpreter."""
    lean = Path(run(["lean", "--print-prefix"]).strip()).resolve(strict=True)
    roots, report = native_dependencies([ROOT / "build/sqlite-parser",
        ROOT / "build/sqlite-parser-3.46.0",
        ROOT / ".lake/build/bin/migration-proof-checker", lean / "bin/lean"], lean)
    (ROOT / "build/nix-runtime-roots").write_text("".join(str(path) + "\n" for path in sorted(roots)))
    (ROOT / "build/native-dependencies.txt").write_text(report)
    print(f"Recorded {len(roots)} exact native Nix runtime roots")


if __name__ == "__main__":
    main()
