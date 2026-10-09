"""Build the SQLite parser library: one shared library with a parser for each grammar.

For each release in `parser/dialects.json`, the build checks the vendored sources,
extracts the grammar options and computes the grammar identity of each dialect. It
fails when the dialect table records another identity. It then generates one Lemon
parser for each distinct identity, compiles it with its release's tokenizer, links all
grammars into one library, and checks that the library exports only the public API.
"""

import argparse
import os
from pathlib import Path
import shlex
import subprocess
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from parser.dialect_table import Dialect, check_dialect, check_release, grammar_identity, load_table
from parser.generate import generate
from parser.grammar_sources import ReleaseSources, read_release
from parser.library_metadata import Grammar, grammar_size, metadata, write_sources

PARSER = Path(__file__).resolve().parent
"""The parser source directory with the library's C files and the vendored releases."""
PUBLIC_API = frozenset({"sqlite_verifier_parser_metadata", "sqlite_verifier_parser_parse",
                        "sqlite_verifier_parser_free"})
"""The only symbols that the library exports; see `parser/library.h`."""
PREFIX_DIGITS = 16
"""The identity digits in a grammar's symbol prefix and work directory; the build fails if two
identities share them."""
STEP_TIMEOUT_SECONDS = 600
"""The limit for one Lemon or compiler run; a sanitizer build of sqlite3.c is the slowest."""
LIBRARY_NAME = "libsqlite-verifier-parser" + (".dylib" if sys.platform == "darwin" else ".so")
"""The file name of the library on this platform."""


def run(command: list[str], output: Path | None = None) -> None:
    """Run one build step; write its standard output to output when given."""
    with open(output, "w") if output else open(os.devnull, "w") as stream:
        subprocess.run(command, check=True, stdout=stream, timeout=STEP_TIMEOUT_SECONDS)


class ReleaseBuild:
    """The Lemon outputs of one release, made in its own work directory."""

    def __init__(self, sources: ReleaseSources, directory: Path, work: Path, compiler: str) -> None:
        """Build the release's Lemon and export its preprocessed grammar and production list.

        Lemon is a build tool, so it gets no library flags: the sanitizers check the library.
        """
        self.sources = sources
        self.directory = directory
        work.mkdir(parents=True)
        lemon = work / "lemon"
        run([compiler, str(directory / "lemon.c"), "-o", str(lemon)])
        self.lemon = lemon
        run([str(lemon), "-q", f"-d{work}", f"-T{directory / 'lempar.c'}", str(directory / "parse.y")])
        self.header = (work / "parse.h").read_text()
        run([str(lemon), "-E", str(directory / "parse.y")], work / "preprocessed.y")
        self.preprocessed = (work / "preprocessed.y").read_text()
        run([str(lemon), "-g", str(directory / "parse.y")], work / "grammar.y")
        self.grammar = (work / "grammar.y").read_text()

    def generate_grammar(self, identity: str, work: Path) -> Grammar:
        """Generate the grammar's parser with a unique prefix and check its production count."""
        prefix = "Syntax_" + identity[:PREFIX_DIGITS]
        work.mkdir()
        generate(self.preprocessed, self.grammar, self.header,
                 (self.directory / "sqlite3.c").read_text(), work / "syntax.y", prefix)
        run([str(self.lemon), "-q", f"-T{self.directory / 'lempar.c'}", str(work / "syntax.y")])
        productions, tokens = grammar_size((work / "syntax.c").read_text(), (work / "syntax.h").read_text())
        exported = sum(1 for line in self.grammar.splitlines() if "::=" in line)
        if productions != exported:
            raise ValueError(f"The generated parser for {self.sources.version} has {productions} "
                             f"productions, but Lemon's grammar export has {exported}")
        return Grammar(identity, prefix, productions, tokens)


def exported_symbols(library: Path) -> set[str]:
    """Return the names of the symbols that the shared library defines and exports."""
    darwin = sys.platform == "darwin"
    command = ["nm", "-gU", str(library)] if darwin else ["nm", "-D", "--defined-only", str(library)]
    output = subprocess.run(command, check=True, capture_output=True, text=True,
                            timeout=STEP_TIMEOUT_SECONDS).stdout
    names = {line.split()[-1] for line in output.splitlines() if line.strip()}
    return {name[1:] if darwin and name.startswith("_") else name for name in names}


def build(table_path: Path, output: Path, work: Path, compiler: list[str], check_exports: bool) -> None:
    """Check the dialect table against the sources and build the library into output."""
    table = load_table(table_path)
    releases: dict[str, ReleaseBuild] = {}
    for release in table.releases:
        directory = PARSER / release.sources
        sources = read_release(directory)
        check_release(release, sources)
        releases[release.version] = ReleaseBuild(sources, directory, work / f"release-{release.version}", compiler[0])
    grammars: dict[str, tuple[Grammar, ReleaseBuild]] = {}
    for dialect in table.dialects:
        built = releases.get(dialect.version)
        if built is None:
            raise ValueError(f"parser/dialects.json has a dialect of release {dialect.version}, "
                             "which its release list does not name")
        check_dialect(dialect, built.sources,
                      grammar_identity(built.preprocessed, built.sources, dialect.grammar_options))
        if dialect.grammar not in grammars:
            grammar = built.generate_grammar(dialect.grammar, work / f"grammar-{dialect.grammar[:PREFIX_DIGITS]}")
            grammars[dialect.grammar] = (grammar, built)
    if len({grammar.prefix for grammar, _ in grammars.values()}) != len(grammars):
        raise ValueError(f"Two grammar identities share their first {PREFIX_DIGITS} digits; increase PREFIX_DIGITS")
    write_sources(work, metadata([built.sources for built in releases.values()], list(table.dialects),
                                 [grammar for grammar, _ in grammars.values()]),
                  [grammar for grammar, _ in grammars.values()])
    link(output, work, compiler, grammars, check_exports)


def link(output: Path, work: Path, compiler: list[str], grammars: dict[str, tuple[Grammar, "ReleaseBuild"]],
         check_exports: bool) -> None:
    """Compile each grammar's tokenizer and parser and the API, and link them into one library."""
    flags = [*compiler, "-std=c99", "-fPIC", "-fvisibility=hidden", "-c", f"-I{PARSER}"]
    objects: list[str] = []
    for grammar, built in grammars.values():
        directory = work / f"grammar-{grammar.identity[:PREFIX_DIGITS]}"
        for unit in ("library_tokenizer", "library_grammar"):
            target = directory / f"{unit}.o"
            run([*flags, f"-DGRAMMAR_PREFIX={grammar.prefix}", f"-I{directory}", f"-I{built.directory}",
                 str(PARSER / f"{unit}.c"), "-o", str(target)])
            objects.append(str(target))
    run([*flags, f"-I{work}", str(PARSER / "library.c"), "-o", str(work / "library.o")])
    (output / "lib").mkdir(parents=True)
    (output / "include").mkdir()
    library = output / "lib" / LIBRARY_NAME
    shared = ["-dynamiclib"] if sys.platform == "darwin" else ["-shared"]
    system = [] if sys.platform == "darwin" else ["-lm", "-lpthread", "-ldl"]
    run([*compiler, *shared, "-o", str(library), *objects, str(work / "library.o"), *system])
    (output / "include" / "sqlite-verifier-parser.h").write_text((PARSER / "library.h").read_text())
    if check_exports and exported_symbols(library) != PUBLIC_API:
        raise ValueError(f"{library} exports {sorted(exported_symbols(library))}, "
                         f"but only the public API {sorted(PUBLIC_API)} may be exported")


def main() -> None:
    """Build the library from the command line; the C compiler comes from $CC."""
    cli = argparse.ArgumentParser(description=__doc__)
    cli.add_argument("--table", type=Path, default=PARSER / "dialects.json")
    cli.add_argument("--output", type=Path, required=True)
    cli.add_argument("--work", type=Path, required=True)
    cli.add_argument("--cflags", default="-O1", help="C compiler and linker flags")
    cli.add_argument("--no-export-check", action="store_true",
                     help="skip the export check; sanitizer runtimes export their own symbols")
    arguments = cli.parse_args()
    compiler = [os.environ.get("CC", "cc"), *shlex.split(arguments.cflags)]
    build(arguments.table, arguments.output, arguments.work, compiler, not arguments.no_export_check)


if __name__ == "__main__":
    main()
