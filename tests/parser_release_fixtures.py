"""Synthetic vendored releases for the unit tests of the parser library build.

A release directory holds the files that `parser/grammar_sources.py` reads, with a
matching `sha256.json`, so the tests can change one input at a time.
"""

import hashlib
import json
from pathlib import Path

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
