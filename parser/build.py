"""Build the pinned upstream tokenizer and syntax-only Lemon parser."""

import os
import hashlib
import json
import re
import subprocess
from pathlib import Path

from generate import generate

ROOT = Path(__file__).resolve().parent.parent
BUILD = ROOT / "build" / "parser"
UPSTREAM = ROOT / "parser" / "upstream"


def run(arguments: list[str]) -> str:
    """Run a bounded build tool and retain failures as actionable diagnostics."""
    return subprocess.run(arguments, cwd=ROOT, check=True, text=True,
                          stdout=subprocess.PIPE, timeout=90).stdout


def main() -> None:
    """Generate from upstream grammar before compiling the independently named parser."""
    BUILD.mkdir(parents=True, exist_ok=True)
    hashes: dict[str, str] = json.loads((UPSTREAM / "sha256.json").read_text())
    for filename, expected in hashes.items():
        if hashlib.sha256((UPSTREAM / filename).read_bytes()).hexdigest() != expected:
            raise ValueError(f"Pinned upstream file changed: {filename}")
    cc = os.environ.get("CC", "cc")
    lemon = str(BUILD / "lemon")
    run([cc, str(UPSTREAM / "lemon.c"), "-o", lemon])
    original = str(UPSTREAM / "parse.y")
    run([lemon, "-q", "-d" + str(BUILD), "-T" + str(UPSTREAM / "lempar.c"), original])
    token_pattern = r"#define TK_(\w+)\s+(\d+)"
    grammar_tokens = dict(re.findall(token_pattern, (BUILD / "parse.h").read_text()))
    native_tokens = dict(re.findall(token_pattern, (UPSTREAM / "sqlite3.c").read_text()))
    if grammar_tokens != native_tokens:
        raise ValueError("Upstream grammar and amalgamation token inventories differ")
    generate(run([lemon, "-E", original]), run([lemon, "-g", original]),
             (BUILD / "parse.h").read_text(), BUILD / "syntax.y")
    run([lemon, "-q", "-T" + str(UPSTREAM / "lempar.c"), str(BUILD / "syntax.y")])
    includes = ["-I" + str(ROOT / "parser"), "-I" + str(BUILD)]
    for filename, source in [("tokenizer", ROOT / "parser" / "tokenizer.c"),
                             ("syntax", BUILD / "syntax.c"),
                             ("main", ROOT / "parser" / "main.c")]:
        run([cc, "-std=c99", "-O1", *includes, "-c", str(source),
             "-o", str(BUILD / (filename + ".o"))])
    run([cc, *(str(BUILD / (name + ".o")) for name in ["tokenizer", "syntax", "main"]),
         "-lm", "-lpthread", "-ldl", "-o", str(ROOT / "build" / "sqlite-parser")])


if __name__ == "__main__":
    main()
