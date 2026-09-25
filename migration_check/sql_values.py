"""Translate only literal stored values whose SQLite representation is explicit."""

import re
from typing import TypeAlias

from .sql_tree import Node, Tree

SqlValue: TypeAlias = int | str | bytes | None


def literal(tree: Tree, node: Node) -> SqlValue:
    """Reject expressions, parameters, floats and oversized integers instead of approximating."""
    children = tree.children(node)
    sign = 1
    if len(children) == 2 and children[0].symbol in {'MINUS', 'PLUS'} and children[1].symbol == 'expr':
        sign = -1 if children[0].symbol == 'MINUS' else 1
        children = tree.children(children[1])
        signed = True
    else:
        signed = False
    if len(children) != 1 or children[0].symbol != 'term':
        raise tree.unsupported(node, 'Only NULL, decimal int64, text and blob literals are supported')
    tokens = tree.children(children[0])
    if len(tokens) != 1:
        raise tree.unsupported(node, 'Unsupported literal production')
    token = tokens[0]
    text = tree.text(token)
    if token.symbol == 'INTEGER' and re.fullmatch(r'[0-9]+', text):
        digits = text.lstrip('0') or '0'
        if len(digits) <= 19:
            value = sign * int(digits)
            if -(2 ** 63) <= value < 2 ** 63:
                return value
        raise tree.unsupported(node, 'Integer literal is outside signed 64-bit storage')
    if not signed:
        if token.symbol == 'NULL':
            return None
        if token.symbol == 'STRING' and text.startswith("'") and text.endswith("'"):
            return text[1:-1].replace("''", "'")
        if token.symbol == 'BLOB' and re.fullmatch(r"[xX]'(?:[0-9a-fA-F]{2})*'", text):
            return bytes.fromhex(text[2:-1])
    raise tree.unsupported(node, 'Only NULL, decimal int64, text and blob literals are supported')


def lean_value(value: SqlValue) -> str:
    """Use bytes for SQLite TEXT/BLOB values and never interpolate executable source."""
    if value is None:
        return '.null'
    if isinstance(value, int):
        return f'.integer ({value})'
    kind, data = ('text', value.encode('utf-8')) if isinstance(value, str) else ('blob', value)
    return f'.{kind} [' + ', '.join(map(str, data)) + ']'
