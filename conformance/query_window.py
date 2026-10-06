"""Locate outer query windows without frontend admission or SQL evaluation."""

from dataclasses import dataclass
import re


@dataclass(frozen=True)
class Token:
    """Original spans and nesting keep comments/quoted keywords out of clause detection."""
    text: str
    start: int
    end: int
    depth: int


ASCII_UPPER = str.maketrans("abcdefghijklmnopqrstuvwxyz", "ABCDEFGHIJKLMNOPQRSTUVWXYZ")


# Keep SQLite's EOF comments and complete Tcl-style named parameter tokens intact.
TOKEN = re.compile(r"--[^\n]*|/\*.*?(?:\*/|$)|'(?:''|[^'])*'|\"(?:\"\"|[^\"])*\"|"
                   r"`(?:``|[^`])*`|\[[^]]*\]|\?[0-9]*|"
                   r"[:@$](?:(?:::)*[\w$\x80-\U0010ffff])+(?:::)*(?:\([^\x09-\x0d\x20)]*\))?|"
                   r"::|[\w]+|[^\s]", re.S)


def tokens(sql: str) -> list[Token]:
    """Tokenize only clause boundaries; SQLite remains the syntax authority."""
    result: list[Token] = []
    depth = 0
    for match in TOKEN.finditer(sql):
        text = match.group()
        if text.startswith(("--", "/*")):
            continue
        if text == ")":
            depth -= 1
        result.append(Token(text, match.start(), match.end(), depth))
        if text == "(":
            depth += 1
    return result


def numbered_parameters(sql: str) -> str:
    """Keep SQLite slot identities when a LIMIT expression is removed from a query."""
    source = tokens(sql)
    if source:
        last = source[-1]
        sql = sql[:last.start if last.text == ";" else last.end]
    highest = 0
    named: dict[str, int] = {}
    pieces: list[str] = []
    previous = 0
    for token in source:
        value = token.text
        if not value.startswith(("?", ":", "@", "$")):
            continue
        if value.startswith("?"):
            index = int(value[1:]) if value[1:] else highest + 1
        else:
            index = named.setdefault(value, highest + 1)
        highest = max(highest, index)
        pieces.extend((sql[previous:token.start], f"?{index}"))
        previous = token.end
    return "".join(pieces) + sql[previous:]


def window(sql: str) -> tuple[str, str, str, str]:
    """Return the uncut query, outer ordering, limit and offset expressions."""
    sql = numbered_parameters(sql).rstrip().removesuffix(";")
    outer = [token for token in tokens(sql) if token.depth == 0]
    order = next((token.start for token, following in zip(outer, outer[1:])
                  if token.text.translate(ASCII_UPPER) == "ORDER" and following.text.translate(ASCII_UPPER) == "BY"), None)
    limit = next((token for token in outer if token.text.translate(ASCII_UPPER) == "LIMIT"), None)
    end = limit.start if limit else len(sql)
    ordering = sql[order:end] if order is not None else ""
    if not limit:
        return sql, ordering, "-1", "0"
    bounds = [token for token in outer if token.start >= limit.end]
    separator = next((token for token in bounds if token.text.translate(ASCII_UPPER) == "OFFSET" or token.text == ","), None)
    if separator:
        first, second = sql[limit.end:separator.start], sql[separator.end:]
        count, offset = (second, first) if separator.text == "," else (first, second)
    else:
        count, offset = sql[limit.end:], "0"
    return sql[:end], ordering, count, offset


def identifier_name(value: str) -> str:
    """Remove exactly one SQLite identifier quote pair, preserving punctuation inside."""
    if value.startswith("["):
        return value[1:-1]
    if value.startswith(('"', "`")):
        quote = value[0]
        return value[1:-1].replace(quote * 2, quote)
    return value


def projected_order(ordering: str, columns: list[str], sql: str) -> str:
    """Resolve simple projected keys/ordinals; refuse hidden or ambiguous sort keys."""
    outer = [token for token in tokens(sql) if token.depth == 0]
    select = next((index for index, token in enumerate(outer) if token.text.translate(ASCII_UPPER) == "SELECT"), None)
    projection: list[list[str]] = [[]]
    if select is not None:
        for token in outer[select + 1:]:
            if token.text.translate(ASCII_UPPER) == "FROM":
                break
            if token.text == ",":
                projection.append([])
            elif token.text.translate(ASCII_UPPER) not in {"DISTINCT", "ALL"}:
                projection[-1].append(token.text)
    source = tokens(ordering)
    terms: list[list[Token]] = [[]]
    for token in source[2:]:  # ORDER BY
        if token.text == "," and token.depth == 0:
            terms.append([])
        else:
            terms[-1].append(token)
    result: list[str] = []
    for term in terms:
        words = [token.text for token in term]
        suffix: list[str] = []
        if len(words) >= 2 and words[-2].translate(ASCII_UPPER) == "NULLS" and words[-1].translate(ASCII_UPPER) in {"FIRST", "LAST"}:
            suffix[:0], words = words[-2:], words[:-2]
        if words and words[-1].translate(ASCII_UPPER) in {"ASC", "DESC"}:
            suffix[:0], words = words[-1:], words[:-1]
        if len(words) >= 2 and words[-2].translate(ASCII_UPPER) == "COLLATE":
            suffix[:0], words = words[-2:], words[:-2]
        if len(words) == 1 and re.fullmatch(r"[0-9]+", words[0]):
            index = int(words[0]) - 1
            name = columns[index] if 0 <= index < len(columns) else ""
        elif len(words) == 3 and words[1] == ".":
            projected = next((entry for entry in projection if entry == ["*"] or
                entry == [words[0], ".", "*"] or entry[:3] == words and
                (len(entry) in {3, 4} or len(entry) == 5 and entry[3].translate(ASCII_UPPER) == "AS")), None)
            if projected is None:
                raise ValueError("tie structure not observable: qualified key is not projected unchanged")
            name = identifier_name(projected[-1] if len(projected) in {4, 5} else words[-1])
        elif len(words) == 1:
            name = identifier_name(words[0])
        else:
            raise ValueError("tie structure not observable: sort key is not a projected name")
        matches = [column for column in columns if column.translate(ASCII_UPPER) == name.translate(ASCII_UPPER)]
        if len(matches) != 1:
            raise ValueError("tie structure not observable: sort key is hidden or ambiguous")
        result.append('"' + matches[0].replace('"', '""') + '" ' + " ".join(suffix))
    return ", ".join(result)
