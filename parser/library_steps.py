"""The checks and generated files of the parser library build, one command for each Nix step.

`build-support/parser-library.nix` builds the library: one derivation for each release,
one for each distinct grammar identity and one that links them. Nix runs Lemon and the C
compiler. These commands do the work in between, which needs a program:

- `hashes`: check the vendored files of a release against `sha256.json`;
- `release`: extract the release's grammar options, compute the grammar identity of
  each of its dialects and fail when the dialect table records another one;
- `grammar`: check the production count of a generated parser against Lemon's grammar
  export and record the grammar's size;
- `sources`: write the grammar list and the metadata document that `library.c` includes;
- `exports`: fail unless the linked library exports exactly the public API.
"""

import argparse
from dataclasses import asdict
import json
from pathlib import Path
import subprocess
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from parser.dialect_table import DialectTable, check_dialect, check_release, grammar_identity, load_table
from parser.grammar_sources import check_hashes, read_release
from parser.library_metadata import Grammar, ReleaseRecord, grammar_size, metadata, write_sources

PUBLIC_API = frozenset({"sqlite_verifier_parser_metadata", "sqlite_verifier_parser_parse",
                        "sqlite_verifier_parser_free"})
"""The only symbols that the library exports; see `parser/library.h`."""
NM_TIMEOUT_SECONDS = 60
"""The limit for listing the symbols of the linked library."""


def release_record(directory: Path, table: DialectTable, preprocessed: str) -> ReleaseRecord:
    """Check the dialects of the one release in table against its sources in directory.

    `preprocessed` is Lemon's `-E` output of the release's `parse.y`. A release step reads
    a table with only its own release and dialects, so a new release in
    `parser/dialects.json` does not change the steps of the other releases.
    """
    if len(table.releases) != 1:
        raise ValueError(f"The release step got a dialect table with {len(table.releases)} releases; "
                         "build-support/parser-library.nix must pass only the release that it builds")
    sources = read_release(directory)
    check_release(table.releases[0], sources)
    for dialect in table.dialects:
        check_dialect(dialect, sources, grammar_identity(preprocessed, sources, dialect.grammar_options))
    return ReleaseRecord(sources.version, sources.source_id, sources.grammar_options)


def grammar_record(directory: Path, identity: str, prefix: str) -> Grammar:
    """Check the generated parser in directory against Lemon's grammar export there."""
    productions, tokens = grammar_size((directory / "syntax.c").read_text(),
                                       (directory / "syntax.h").read_text())
    exported = sum(1 for line in (directory / "grammar.y").read_text().splitlines() if "::=" in line)
    if productions != exported:
        raise ValueError(f"The generated parser of grammar {identity} has {productions} productions, "
                         f"but Lemon's grammar export has {exported}; check parser/generate.py")
    return Grammar(identity, prefix, productions, tokens)


def library_sources(table: DialectTable, releases: list[ReleaseRecord], grammars: list[Grammar],
                    output: Path) -> None:
    """Write the C inputs of `library.c` for these releases and grammars into output."""
    if {dialect.grammar for dialect in table.dialects} != {grammar.identity for grammar in grammars}:
        raise ValueError(f"The library step got grammars {sorted(grammar.identity for grammar in grammars)}, "
                         f"but parser/dialects.json names {sorted({d.grammar for d in table.dialects})}; "
                         "build-support/parser-library.nix must pass one grammar for each identity")
    if len({grammar.prefix for grammar in grammars}) != len(grammars):
        raise ValueError("Two grammars have the same symbol prefix; increase prefixDigits in "
                         "build-support/parser-library.nix")
    if [release.version for release in releases] != [release.version for release in table.releases]:
        raise ValueError(f"The library step got release records {[r.version for r in releases]}, but "
                         f"parser/dialects.json lists {[r.version for r in table.releases]}; "
                         "build-support/parser-library.nix must pass them in the table's order")
    write_sources(output, metadata(releases, list(table.dialects), grammars), grammars)


def exported_symbols(library: Path, darwin: bool) -> set[str]:
    """Return the names of the symbols that the shared library defines and exports."""
    command = ["nm", "-gU", str(library)] if darwin else ["nm", "-D", "--defined-only", str(library)]
    output = subprocess.run(command, check=True, capture_output=True, text=True,
                            timeout=NM_TIMEOUT_SECONDS).stdout
    names = {line.split()[-1] for line in output.splitlines() if line.strip()}
    return {name[1:] if darwin and name.startswith("_") else name for name in names}


def read_release_record(path: Path) -> ReleaseRecord:
    """Read a release record that the `release` step wrote."""
    value = json.loads(path.read_text())
    return ReleaseRecord(value["version"], value["source_id"], tuple(value["grammar_options"]))


def check_exports(library: Path) -> None:
    """Fail unless the library exports exactly the public API."""
    exported = exported_symbols(library, sys.platform == "darwin")
    if exported != PUBLIC_API:
        raise ValueError(f"{library} exports {sorted(exported)}, but only the public API "
                         f"{sorted(PUBLIC_API)} may be exported")


def main() -> None:
    """Run one build step from the command line."""
    cli = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    steps = cli.add_subparsers(dest="step", required=True)
    steps.add_parser("hashes").add_argument("directory", type=Path)
    release = steps.add_parser("release")
    for name in ("--directory", "--table", "--preprocessed", "--output"):
        release.add_argument(name, type=Path, required=True)
    grammar = steps.add_parser("grammar")
    grammar.add_argument("--directory", type=Path, required=True)
    grammar.add_argument("--identity", required=True)
    grammar.add_argument("--prefix", required=True)
    sources = steps.add_parser("sources")
    sources.add_argument("--table", type=Path, required=True)
    sources.add_argument("--release", type=Path, action="append", default=[])
    sources.add_argument("--grammar", type=Path, action="append", default=[])
    sources.add_argument("--output", type=Path, required=True)
    steps.add_parser("exports").add_argument("library", type=Path)
    arguments = cli.parse_args()
    if arguments.step == "hashes":
        check_hashes(arguments.directory)
    elif arguments.step == "release":
        record = release_record(arguments.directory, load_table(arguments.table),
                                arguments.preprocessed.read_text())
        arguments.output.write_text(json.dumps(asdict(record)))
    elif arguments.step == "grammar":
        record = grammar_record(arguments.directory, arguments.identity, arguments.prefix)
        (arguments.directory / "grammar.json").write_text(json.dumps(asdict(record)))
    elif arguments.step == "sources":
        library_sources(load_table(arguments.table), [read_release_record(path) for path in arguments.release],
                        [Grammar(**json.loads(path.read_text())) for path in arguments.grammar], arguments.output)
    else:
        check_exports(arguments.library)


if __name__ == "__main__":
    main()
