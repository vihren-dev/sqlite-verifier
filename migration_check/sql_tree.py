"""Read the pinned parser's concrete tree against one immutable SQL byte snapshot."""

from dataclasses import dataclass
import json
from pathlib import Path
import subprocess
from tempfile import TemporaryDirectory
from collections.abc import Iterator

from .diagnostics import Rejection


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

    def unsupported(self, node: Node, message: str) -> Rejection:
        """Locate a semantic admission failure in the original input."""
        return Rejection("UNSUPPORTED", message, source=self.source,
                         start=node.start, end=node.end)


def parse(parser: Path, sql: bytes, source: str, expected_profile: str = "3.51.0") -> Tree:
    """Parse a copied snapshot, never a caller-controlled file that may change mid-run."""
    with TemporaryDirectory(prefix="migration-parse-") as directory:
        snapshot = Path(directory) / "input.sql"
        snapshot.write_bytes(sql)
        try:
            result = subprocess.run([str(parser), str(snapshot)], capture_output=True,
                                    text=True, timeout=5)
        except subprocess.TimeoutExpired as error:
            raise Rejection("UNVERIFIED", "SQL parser exceeded its time limit", source=source) from error
    try:
        payload = json.loads(result.stdout)
        if payload["status"] != "PARSED":
            status = "UNVERIFIED" if payload["status"] == "RESOURCE_LIMIT" else "INPUT_ERROR"
            raise Rejection(status, str(payload.get("message", "SQL parser rejected input")),
                            source=source, start=int(payload.get("offset", 0)))
        if result.returncode != 0 or payload["profile"] != expected_profile:
            raise ValueError("Parser build/profile mismatch")
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
        raise Rejection("UNVERIFIED", f"Parser output is unusable: {error}", source=source) from error
