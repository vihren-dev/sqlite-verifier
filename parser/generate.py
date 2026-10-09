"""Replace upstream Lemon actions with generic syntax-tree construction."""

import argparse
import re
from pathlib import Path


def generate(preprocessed: str, grammar: str, header: str, native: str, target: Path,
             name: str = "Syntax") -> None:
    """Preserve productions and parser directives, replacing only semantic actions.

    `name` is Lemon's function prefix. The parser library links several grammars into
    one library, so each grammar there gets its own prefix.
    """
    tokens = re.findall(r"#define TK_(\w+)\s+(\d+)", header)
    if not tokens or dict(tokens) != dict(re.findall(r"#define TK_(\w+)\s+(\d+)", native)):
        raise ValueError("Upstream grammar and amalgamation token inventories differ")
    comments_removed = re.sub(r"/\*.*?\*/|//[^\n]*", "", preprocessed, flags=re.S)
    directives = re.findall(
        r"%(?:left|right|nonassoc|fallback|wildcard)\s+[^.]+\.", comments_removed
    )
    lines = [
        '%include {#include "runtime.h"\n#define YYNOERRORRECOVERY 1}',
        f"%name {name}", "%start_symbol input", "%token_prefix P_", "%token_type {int}",
        "%default_type {int}", "%extra_argument {Context *ctx}",
        "%stack_size 0", "%realloc realloc", "%free free",
        "%syntax_error {if(!ctx->error) ctx->error = 1;}",
        "%parse_failure {if(!ctx->error) ctx->error = 1;}",
        "%stack_overflow {ctx->error = 2;}",
        "%parse_accept {ctx->accepted = 1;}",
        "%token " + " ".join(name for name, _ in tokens) + ".",
        *directives,
    ]
    rules = [line for line in grammar.splitlines() if "::=" in line]
    for rule in rules:
        match = re.fullmatch(r"(\w+) ::=\s*(.*?)\.(?: \[(\w+)\])?", rule)
        if match is None:
            raise ValueError(f"Unexpected upstream production: {rule}")
        lhs, rhs, precedence = match.groups()
        symbols = rhs.split()
        aliases = [f"v{i}" for i in range(len(symbols))]
        production = " ".join(f"{symbol}({alias})" for symbol, alias in zip(symbols, aliases))
        children = "(int[]){" + ",".join(aliases) + "}" if aliases else "NULL"
        action = f'A = branch(ctx, "{lhs}", {len(aliases)}, {children});'
        if lhs == "input":
            action += "ctx->root = A;"
        suffix = f" [{precedence}]" if precedence else ""
        lines.append(f"{lhs}(A) ::= {production}.{suffix} {{{action}}}")
    target.write_text("\n".join(lines) + "\n")
    target.with_name("token_names.inc").write_text(
        "\n".join(f'case TK_{name}: return "{name}";' for name, _ in tokens)
    )
    target.with_name("token_map.inc").write_text(
        "\n".join(f"case {number}: return P_{name};" for name, number in tokens)
    )


if __name__ == "__main__":
    cli = argparse.ArgumentParser(description=__doc__)
    cli.add_argument("upstream", type=Path)
    cli.add_argument("directory", type=Path)
    cli.add_argument("--name", default="Syntax", help="Lemon function prefix")
    args = cli.parse_args()
    generate((args.directory / "preprocessed.y").read_text(),
             (args.directory / "grammar.y").read_text(),
             (args.directory / "parse.h").read_text(),
             (args.upstream / "sqlite3.c").read_text(), args.directory / "syntax.y", args.name)
