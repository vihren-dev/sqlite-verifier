"""The parser library build reads grammar options, computes identities and checks the dialect table.

These tests check `parser/grammar_sources.py`, `parser/dialect_table.py` and
`parser/library_metadata.py` with small synthetic release directories. The Nix build of
`parserLibrary` runs the same code on the vendored releases.
"""

import hashlib
import json
from pathlib import Path

import pytest

from parser.dialect_table import Dialect, Release, check_dialect, check_release, grammar_identity, load_table
from parser.grammar_sources import C_CONDITIONAL, LEMON_CONDITIONAL, read_release, conditional_macros
from parser.library_metadata import Grammar, c_string, grammar_size, metadata, write_sources

pytestmark = [pytest.mark.unit, pytest.mark.parser]
AMALGAMATION = """/* before */
SQLITE_PRIVATE const unsigned char sqlite3UpperToLower[] = {
#ifdef SQLITE_ASCII
  0, 1
#endif
};
SQLITE_PRIVATE const unsigned char sqlite3CtypeMap[256] = {
  0, 1
};
/* other global.c code */
/************** Begin file tokenize.c ***************************************/
#ifndef SQLITE_OMIT_WINDOWFUNC
static int analyzeWindowKeyword(void){ return 0; }
#endif
SQLITE_PRIVATE int sqlite3RunParser(Parse *pParse, const char *zSql){
#ifdef SQLITE_DEBUG
#endif
}
"""
"""The parts of sqlite3.c that the build reads: the tables, the tokenizer and code after it."""


def release(directory: Path, *, version: str = "3.51.0", grammar: str = "%ifndef SQLITE_OMIT_CTE\n%endif\n",
            amalgamation: str = AMALGAMATION) -> Path:
    """Write a synthetic release directory with a matching sha256.json."""
    directory.mkdir()
    (directory / "sqlite3.h").write_text(f'#define SQLITE_VERSION        "{version}"\n'
                                         '#define SQLITE_SOURCE_ID      "2025-11-04 source"\n')
    (directory / "sqlite3.c").write_text(amalgamation)
    (directory / "parse.y").write_text(grammar)
    hashes = {name: hashlib.sha256((directory / name).read_bytes()).hexdigest()
              for name in ("sqlite3.h", "sqlite3.c", "parse.y")}
    (directory / "sha256.json").write_text(json.dumps(hashes))
    return directory


def test_conditional_macros_reads_lemon_and_c_conditionals() -> None:
    """Grammar options come from every conditional form; a test of a macro value is refused."""
    lemon = "%ifdef A\n%ifndef B\n%if C || !D\n%endif\n%else\n"
    assert conditional_macros(lemon, LEMON_CONDITIONAL) == {"A", "B", "C", "D"}
    c = "#ifdef E\n# if defined(F) && \\\n  !defined(G) /* comment H */\n#elif I\n#endif\n"
    assert conditional_macros(c, C_CONDITIONAL) == {"E", "F", "G", "I"}
    with pytest.raises(ValueError, match="macro value"):
        conditional_macros("%if X==2\n", LEMON_CONDITIONAL)


def test_read_release_extracts_options_from_parser_sources_only(tmp_path: Path) -> None:
    """The tokenizer section ends at sqlite3RunParser, so its SQLITE_DEBUG test is no grammar option."""
    sources = read_release(release(tmp_path / "upstream"))
    assert (sources.version, sources.source_id) == ("3.51.0", "2025-11-04 source")
    assert sources.grammar_options == ("SQLITE_ASCII", "SQLITE_OMIT_CTE", "SQLITE_OMIT_WINDOWFUNC")
    assert "analyzeWindowKeyword" in sources.tokenizer and "sqlite3RunParser" not in sources.tokenizer
    assert sources.character_tables.startswith("SQLITE_PRIVATE const unsigned char sqlite3UpperToLower")
    assert sources.character_tables.endswith("  0, 1\n};") and "other global.c" not in sources.character_tables


def test_read_release_refuses_changed_or_incomplete_sources(tmp_path: Path) -> None:
    """A file that differs from sha256.json, or a missing amalgamation marker, fails the build."""
    changed = release(tmp_path / "changed")
    (changed / "parse.y").write_text("%ifdef OTHER\n")
    with pytest.raises(ValueError, match="differs from its digest"):
        read_release(changed)
    without_tokenizer = AMALGAMATION.replace("Begin file tokenize.c", "Begin file other.c")
    with pytest.raises(ValueError, match="tokenizer"):
        read_release(release(tmp_path / "incomplete", amalgamation=without_tokenizer))


def test_identity_follows_each_input_and_ignores_the_directory(tmp_path: Path) -> None:
    """The grammar, the tokenizer, the tables and the options each change the identity; the
    directory name does not."""
    base = read_release(release(tmp_path / "upstream"))
    same = read_release(release(tmp_path / "upstream-3.51.1"))
    identity = grammar_identity("input ::= cmd.", base, ())
    assert grammar_identity("input ::= cmd.", same, ()) == identity
    tokenizer = read_release(release(tmp_path / "tokenizer", amalgamation=AMALGAMATION.replace(
        "return 0;", "return 1;")))
    tables = read_release(release(tmp_path / "tables", amalgamation=AMALGAMATION.replace("0, 1\n};", "0, 2\n};")))
    assert len({identity, grammar_identity("input ::= ecmd.", base, ()),
                grammar_identity("input ::= cmd.", tokenizer, ()),
                grammar_identity("input ::= cmd.", tables, ()),
                grammar_identity("input ::= cmd.", base, ("SQLITE_OMIT_CTE",))}) == 5


def test_dialect_table_checks(tmp_path: Path) -> None:
    """The build refuses a wrong release label, unknown or unbuilt options and another identity."""
    sources = read_release(release(tmp_path / "upstream"))
    check_release(Release("3.51.0", "upstream"), sources)
    with pytest.raises(ValueError, match="labels it 3.46.0"):
        check_release(Release("3.46.0", "upstream"), sources)
    check_dialect(Dialect("3.51.0", (), "abc"), sources, "abc")
    with pytest.raises(ValueError, match="records abc"):
        check_dialect(Dialect("3.51.0", (), "abc"), sources, "abd")
    with pytest.raises(ValueError, match="not grammar options"):
        check_dialect(Dialect("3.51.0", ("SQLITE_THREADSAFE",), "abc"), sources, "abc")
    with pytest.raises(ValueError, match="only default dialects"):
        check_dialect(Dialect("3.51.0", ("SQLITE_OMIT_CTE",), "abc"), sources, "abc")


def test_load_table_validates_the_structure(tmp_path: Path) -> None:
    """The checked-in table loads; a duplicate dialect or a missing field is refused."""
    table = load_table(Path(__file__).resolve().parents[1] / "parser/dialects.json")
    assert [release.version for release in table.releases] == ["3.51.0", "3.46.0"]
    assert all(not dialect.grammar_options and len(dialect.grammar) == 64 for dialect in table.dialects)
    entry = {"version": "3.51.0", "grammarOptions": [], "grammar": "abc"}
    for dialects, message in (([entry, entry], "dialect twice"), ([{"version": "3.51.0"}], "fields")):
        path = tmp_path / "dialects.json"
        path.write_text(json.dumps({"releases": [{"version": "3.51.0", "sources": "upstream"}],
                                    "dialects": dialects}))
        with pytest.raises(ValueError, match=message):
            load_table(path)


def test_metadata_and_generated_c_sources(tmp_path: Path) -> None:
    """The metadata has the documented fields, and the generated C keeps its exact bytes."""
    sources = read_release(release(tmp_path / "upstream"))
    grammar = Grammar("ab" * 32, "Syntax_" + "ab" * 8, 409, 186)
    document = metadata([sources], [Dialect("3.51.0", (), grammar.identity)], [grammar])
    assert document == {
        "api": 1,
        "releases": [{"version": "3.51.0", "sourceId": "2025-11-04 source",
                      "grammarOptions": ["SQLITE_ASCII", "SQLITE_OMIT_CTE", "SQLITE_OMIT_WINDOWFUNC"]}],
        "dialects": [{"version": "3.51.0", "grammarOptions": [], "grammar": grammar.identity}],
        "grammars": [{"grammar": grammar.identity, "productions": 409, "tokens": 186}]}
    assert c_string('a"b\\c') == '"a\\"b\\\\c"'
    write_sources(tmp_path, document, [grammar])
    assert (tmp_path / "library_grammars.inc").read_text() == f'GRAMMAR({grammar.prefix}, "{grammar.identity}")\n'
    assert grammar_size("#define YYNRULE              409\n", "#define P_SEMI 1\n#define P_ID 2\n") == (409, 2)
