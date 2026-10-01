"""Match ordinary native statements to their original Tcl call boundaries."""

from conformance.case_format import Json
from conformance.query_window import tokens


def join_commands(commands: list[str]) -> str:
    """Keep separate Tcl SQL calls separate even without their own final semicolon."""
    return "\n;\n".join(commands)


def command_ranges(commands: list[str], separator: str = "\n;\n") -> list[tuple[int, int]]:
    """Use UTF-8 byte offsets, matching SQLite's prepared-statement tail."""
    ranges: list[tuple[int, int]] = []
    offset = 0
    for index, command in enumerate(commands):
        end = offset + len(command.encode())
        if index + 1 < len(commands):
            end += len(separator.encode()) - 1
        ranges.append((offset, end))
        offset = end + 1
    return ranges


def readonly_spans(commands: list[str], helpers: list[str]) -> list[tuple[int, int]]:
    """Protect every statement belonging to a Tcl row helper before preparation."""
    return [span for span, helper in zip(command_ranges(commands), helpers, strict=True) if helper != "eval"]


def command_events(record: dict[str, Json], commands: list[str]) -> list[list[dict[str, Json]]]:
    """Reject cross-call statements instead of merging Tcl calls into new SQL."""
    separator = "\n" if record["migrationSql"] == "\n".join(commands) else "\n;\n"
    source = separator.join(commands).encode()
    if record["migrationSql"].encode() != source:
        raise ValueError("Native/Tcl SQL call source differs")
    ranges = command_ranges(commands, separator)
    groups: list[list[dict[str, Json]]] = [[] for _ in commands]
    offset = 0
    for event in record["trace"]:
        sql = event["sql"]
        encoded = sql.encode()
        if source[offset:offset + len(encoded)] != encoded:
            raise ValueError("Native/Tcl SQL call boundaries differ")
        lexical = tokens(sql)
        while lexical and lexical[0].text == ";":
            lexical = lexical[1:]
        if not lexical:
            raise ValueError("Native statement has no observable SQL tokens")
        first = offset + len(sql[:lexical[0].start].encode())
        last = offset + len(sql[:lexical[-1].end].encode())
        index = next((i for i, (start, end) in enumerate(ranges) if start <= first < end), None)
        if index is None or last > ranges[index][1]:
            raise ValueError("Native statement crosses Tcl SQL call boundary")
        groups[index].append(event)
        offset += len(encoded)
    return groups
