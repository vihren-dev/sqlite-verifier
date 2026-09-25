"""Build the pinned upstream tokenizer and syntax-only Lemon parser."""

import hashlib
import json
import re
import subprocess
from pathlib import Path

from generate import generate
from build_cache import current, identity, record

ROOT = Path(__file__).resolve().parent.parent


def run(arguments: list[str]) -> str:
    """Run a bounded build tool and retain failures as actionable diagnostics."""
    return subprocess.run(arguments, cwd=ROOT, check=True, text=True,
                          stdout=subprocess.PIPE, timeout=90).stdout


def build(version: str, source: str, executable: str) -> None:
    """Compile each pinned release with its own grammar, tokenizer and token map."""
    upstream = ROOT / "parser" / source
    directory = ROOT / "build" / ("parser" if version == "3.51.0" else f"parser-{version}")
    directory.mkdir(parents=True, exist_ok=True)
    hashes: dict[str, str] = json.loads((upstream / "sha256.json").read_text())
    for filename, expected in hashes.items():
        if hashlib.sha256((upstream / filename).read_bytes()).hexdigest() != expected:
            raise ValueError(f"Pinned upstream file changed: {filename}")
    cc, inputs, reusable = identity(ROOT, upstream, version, executable)
    outputs = [directory / name for name in (
        "lemon", "parse.c", "parse.h", "syntax.y", "syntax.c", "syntax.h",
        "token_names.inc", "token_map.inc", "tokenizer.o", "syntax.o", "main.o")]
    outputs.append(ROOT / "build" / executable)
    stamp = directory / "build-state.json"
    if reusable and current(stamp, inputs, outputs):
        return
    stamp.unlink(missing_ok=True)
    lemon = str(directory / "lemon")
    run([cc, str(upstream / "lemon.c"), "-o", lemon])
    original = str(upstream / "parse.y")
    run([lemon, "-q", "-d" + str(directory), "-T" + str(upstream / "lempar.c"), original])
    token_pattern = r"#define TK_(\w+)\s+(\d+)"
    grammar_tokens = dict(re.findall(token_pattern, (directory / "parse.h").read_text()))
    native_tokens = dict(re.findall(token_pattern, (upstream / "sqlite3.c").read_text()))
    if grammar_tokens != native_tokens:
        raise ValueError("Upstream grammar and amalgamation token inventories differ")
    generate(run([lemon, "-E", original]), run([lemon, "-g", original]),
             (directory / "parse.h").read_text(), directory / "syntax.y")
    run([lemon, "-q", "-T" + str(upstream / "lempar.c"), str(directory / "syntax.y")])
    includes = ["-I" + str(ROOT / "parser"), "-I" + str(directory), "-I" + str(upstream)]
    for filename, source in [("tokenizer", ROOT / "parser" / "tokenizer.c"),
                             ("syntax", directory / "syntax.c"),
                             ("main", ROOT / "parser" / "main.c")]:
        run([cc, "-std=c99", "-O1", *includes, "-c", str(source),
             "-o", str(directory / (filename + ".o"))])
    run([cc, *(str(directory / (name + ".o")) for name in ["tokenizer", "syntax", "main"]),
         "-lm", "-lpthread", "-ldl", "-o", str(ROOT / "build" / executable)])
    if identity(ROOT, upstream, version, executable)[1:] != (inputs, reusable):
        raise RuntimeError("Parser inputs changed during compilation; retry the build")
    if reusable:
        record(stamp, inputs, outputs)


if __name__ == "__main__":
    build("3.51.0", "upstream", "sqlite-parser")
    build("3.46.0", "upstream-3.46.0", "sqlite-parser-3.46.0")
