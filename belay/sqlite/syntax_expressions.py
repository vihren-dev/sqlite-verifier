"""Map names, literals and expressions of the parser tree to statement syntax.

This is lexical work only: quotes are removed and literal bytes are decoded, as
SQLite's tokenizer and `sqlite3Dequote` do. Names keep their case, and numeric
literals keep their token text, because SQLite's conversion is not lexical.
"""

from .located import Located, constructor, leaf
from .sql_tree import Node, Tree

QUOTES = {'"': '"', "'": "'", "`": "`", "[": "]"}
"""SQLite's quote characters and the character that closes each one."""


def dequote(text: str) -> str:
    """Apply `sqlite3Dequote`: remove a leading quote up to its closing quote and undouble it.

    Text without a leading quote is unchanged. Like SQLite, the result ends at the
    first closing quote, so `"Some" Type` becomes `Some`.
    """
    if not text or text[0] not in QUOTES:
        return text
    close, result, index = QUOTES[text[0]], [], 1
    while index < len(text):
        if text[index] == close:
            if text[index + 1:index + 2] == close:
                result.append(close)
                index += 2
                continue
            break
        result.append(text[index])
        index += 1
    return "".join(result)


def token(tree: Tree, node: Node) -> Node:
    """Return the single token of a one-token production, or refuse the production."""
    children = tree.children(node)
    if len(children) != 1 or children[0].children:
        raise tree.unsupported(node, f"Unsupported SQL form: {node.symbol}; write a plain name or literal")
    return children[0]


def name(tree: Tree, node: Node) -> Located:
    """Decode an `nm` production or a name token as written, with quotes removed."""
    item = node if not node.children else token(tree, node)
    return leaf(dequote(tree.text(item)), node.start, node.end)


def text_bytes(tree: Tree, node: Node) -> list[int]:
    """Decode a STRING token: the UTF-8 bytes between the quotes, with doubled quotes undoubled."""
    return list(dequote(tree.text(node)).encode("utf-8"))


def term(tree: Tree, node: Node) -> Located:
    """Map a `term` production: NULL, a numeric, string or blob literal, or a time keyword."""
    item = token(tree, node)
    text = tree.text(item)
    if item.symbol == "NULL":
        return leaf("null", node.start, node.end)
    if item.symbol in {"INTEGER", "FLOAT", "QNUMBER"}:
        return constructor("numeric", [("text", leaf(text, item.start, item.end))], node.start, node.end)
    if item.symbol == "STRING":
        return constructor("string", [("bytes", leaf(text_bytes(tree, item), item.start, item.end))],
                           node.start, node.end)
    if item.symbol == "BLOB":
        return constructor("blob", [("bytes", leaf(list(bytes.fromhex(text[2:-1])), item.start, item.end))],
                           node.start, node.end)
    if item.symbol == "CTIME_KW":
        return constructor("currentTime", [("keyword", leaf(text, item.start, item.end))], node.start, node.end)
    raise tree.unsupported(node, f"Unsupported literal: {item.symbol}; write NULL, a number, a string or a blob")


def identifier(tree: Tree, node: Node) -> Located:
    """Map an identifier token, and record whether it was written in double quotes."""
    text = tree.text(node)
    return constructor("identifier", [("name", leaf(dequote(text), node.start, node.end)),
                                      ("doubleQuoted", leaf(text.startswith('"'), node.start, node.end))],
                       node.start, node.end)


IDENTIFIER_TOKENS = frozenset("""
    ID INDEXED JOIN_KW
    ABORT ACTION AFTER ANALYZE ASC ATTACH BEFORE BEGIN BY CASCADE CAST COLUMNKW CONFLICT DATABASE DEFERRED DESC
    DETACH DO EACH END EXCLUSIVE EXPLAIN FAIL FOR IGNORE IMMEDIATE INITIALLY INSTEAD LIKE_KW MATCH NO PLAN QUERY
    KEY OF OFFSET PRAGMA RAISE RECURSIVE RELEASE REPLACE RESTRICT ROW ROWS ROLLBACK SAVEPOINT TEMP TRIGGER VACUUM
    VIEW VIRTUAL WITH WITHOUT NULLS FIRST LAST CURRENT FOLLOWING PARTITION PRECEDING RANGE UNBOUNDED EXCLUDE GROUPS
    OTHERS TIES GENERATED ALWAYS MATERIALIZED REINDEX RENAME IF
""".split())
"""The tokens of SQLite's `expr ::= ID|INDEXED|JOIN_KW` production: those three and the
keywords of `%fallback ID` in the pinned `parse.y` of 3.51.0, with its compile options. The
parse tree keeps a fallback keyword's own symbol, so a column named `key` is an `expr` of
one `KEY` token."""


def expression(tree: Tree, node: Node) -> Located:
    """Map an `expr` production that has a syntax constructor, or refuse it with its range."""
    children = tree.children(node)
    symbols = [child.symbol for child in children]
    if symbols == ["term"]:
        return term(tree, children[0])
    if len(symbols) == 1 and symbols[0] in IDENTIFIER_TOKENS:
        return identifier(tree, children[0])
    if symbols in (["MINUS", "expr"], ["PLUS", "expr"]):
        kind = "negate" if symbols[0] == "MINUS" else "positive"
        return constructor(kind, [("operand", expression(tree, children[1]))], node.start, node.end)
    if symbols == ["expr", "EQ", "expr"]:
        return constructor("equals", [("left", expression(tree, children[0])),
                                      ("right", expression(tree, children[2]))], node.start, node.end)
    raise tree.unsupported(node, "Unsupported expression; write a literal, a column name, a sign or an equality")
