"""Read the pinned parser's concrete syntax tree of an SQL text, in this process.

The parser library holds one grammar for each dialect. Python `bytes` cannot change,
so the library reads the caller's bytes directly.
"""

from collections.abc import Iterator
from dataclasses import dataclass

from .dialects import ProfileIdentity, select_grammar
from .errors import SqlError
from .parser_library import ParserLibrary, ParserLibraryError


@dataclass(frozen=True)
class Node:
    """An upstream grammar production and its half-open UTF-8 source span."""

    symbol: str
    start: int
    end: int
    children: tuple[int, ...]


@dataclass(frozen=True)
class Tree:
    """All syntax, including unsupported commands, remains available to admission."""

    source: str
    sql: bytes
    nodes: tuple[Node, ...]
    root: int

    def children(self, node: Node) -> list[Node]:
        """Return the production's children in SQL order."""
        return [self.nodes[index] for index in node.children]

    def text(self, node: Node) -> str:
        """Decode only spans already validated by the upstream UTF-8 tokenizer."""
        return self.sql[node.start:node.end].decode("utf-8")

    def walk(self, node: Node) -> Iterator[Node]:
        """Traverse without consuming Python recursion on long scripts or column lists."""
        pending = [node]
        while pending:
            current = pending.pop()
            yield current
            pending.extend(reversed(self.children(current)))

    def unsupported(self, node: Node, message: str) -> SqlError:
        """Locate a semantic admission failure in the original input."""
        return SqlError("UNSUPPORTED", message, source=self.source,
                         start=node.start, end=node.end)


class ParserResourceLimit(SqlError):
    """The SQL text exceeds the parser's input or syntax-tree size limit.

    The parser did not decide whether the text is valid SQL, so the result is unverified.
    """

    def __init__(self, source: str, offset: int) -> None:
        """Report the limit at the offset where the parser stopped."""
        super().__init__("UNVERIFIED", "SQL exceeds the parser's limits of 1 MiB of input and 200,000 "
                         "syntax-tree nodes; split the SQL into smaller files", source=source, start=offset)


@dataclass(frozen=True)
class SqlParser:
    """A loaded parser library and the grammar identity of one dialect."""

    library: ParserLibrary
    grammar: str

    @classmethod
    def for_profile(cls, library: ParserLibrary, profile: ProfileIdentity) -> "SqlParser":
        """Select the profile's dialect in the library; refuse a profile without one."""
        return cls(library, select_grammar(library.metadata, profile))


def parse(parser: SqlParser, sql: bytes, source: str) -> Tree:
    """Parse sql in-process with the parser's grammar and check the syntax tree."""
    try:
        payload = parser.library.parse(parser.grammar, sql)
    except ParserLibraryError as error:
        raise SqlError("UNVERIFIED", f"SQL parser failed: {error}", source=source) from error
    try:
        if not isinstance(payload, dict):
            raise ValueError("Parser document is not an object")
        if payload["status"] == "RESOURCE_LIMIT":
            raise ParserResourceLimit(source, int(payload.get("offset", 0)))
        if payload["status"] != "PARSED":
            raise SqlError("INPUT_ERROR", "SQLite's grammar rejects the SQL at this offset; correct the "
                           "SQL there and run the command again", source=source,
                           start=int(payload.get("offset", 0)))
        if payload["grammar"] != parser.grammar:
            raise ValueError("Parser result is for another grammar")
        nodes = tuple(Node(item["symbol"], item["start"], item["end"], tuple(item["children"]))
                      for item in payload["nodes"])
        for index, node in enumerate(nodes):
            if (not isinstance(node.symbol, str) or type(node.start) is not int or
                    type(node.end) is not int or not 0 <= node.start <= node.end <= len(sql) or
                    any(type(child) is not int or not 0 <= child < index for child in node.children)):
                raise ValueError("Invalid syntax-tree node")
        root = payload["root"]
        if type(root) is not int or not 0 <= root < len(nodes) or nodes[root].symbol != "input":
            raise ValueError("Invalid syntax-tree root")
        return Tree(source, sql, nodes, root)
    except (ValueError, KeyError, TypeError) as error:
        raise SqlError("UNVERIFIED", f"Parser output is unusable: {error}", source=source) from error
