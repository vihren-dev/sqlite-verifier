"""Replace upstream Lemon actions with generic syntax-tree construction."""

import re
from pathlib import Path


def generate(preprocessed: str, grammar: str, header: str, target: Path) -> None:
    """Preserve productions and parser directives, replacing only semantic actions."""
    tokens = re.findall(r"#define TK_(\w+)\s+(\d+)", header)
    comments_removed = re.sub(r"/\*.*?\*/|//[^\n]*", "", preprocessed, flags=re.S)
    directives = re.findall(
        r"%(?:left|right|nonassoc|fallback|wildcard)\s+[^.]+\.", comments_removed
    )
    lines = [
        '%include {#include "runtime.h"\n#define YYNOERRORRECOVERY 1}',
        "%name Syntax", "%start_symbol input", "%token_prefix P_", "%token_type {int}",
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
