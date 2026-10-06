"""Match ordinary native statements to their original Tcl call boundaries."""

from conformance.case_format import Json
from conformance.query_window import TOKEN, tokens
from conformance.native_bindings import READ_ONLY_TCL_HELPERS


def command_separator(command: str) -> str:
    """Terminate calls without adding SQL source text before an observable statement end."""
    matches = list(TOKEN.finditer(command))
    last = matches[-1] if matches else None
    if last and last.group().startswith("/*") and not last.group().endswith("*/"):
        raise ValueError("SQL call ends in an unterminated block comment")
    return "\n;\n" if last and last.group().startswith("--") and last.end() == len(command) else ";\n"


def join_commands(commands: list[str]) -> str:
    """Keep separate Tcl SQL calls separate even without their own final semicolon."""
    return "".join(command + (command_separator(command) if index + 1 < len(commands) else "")
                   for index, command in enumerate(commands))


def command_ranges(commands: list[str], separator: str | None = None) -> list[tuple[int, int]]:
    """Use UTF-8 byte offsets, matching SQLite's prepared-statement tail."""
    ranges: list[tuple[int, int]] = []
    offset = 0
    for index, command in enumerate(commands):
        end = offset + len(command.encode())
        if index + 1 < len(commands):
            end += len((separator if separator is not None else command_separator(command)).encode()) - 1
        ranges.append((offset, end))
        offset = end + 1
    return ranges


def readonly_spans(commands: list[str], helpers: list[str]) -> list[tuple[int, int]]:
    """Protect every statement belonging to a Tcl row helper before preparation."""
    return [span for span, helper in zip(command_ranges(commands), helpers, strict=True)
            if helper.startswith("aux:") or helper in READ_ONLY_TCL_HELPERS]


def command_events(record: dict[str, Json], commands: list[str]) -> list[list[dict[str, Json]]]:
    """Reject cross-call statements instead of merging Tcl calls into new SQL."""
    source = record["migrationSql"].encode()
    separator = next((value for value in ("\n", "\n;\n") if value.join(commands).encode() == source), None)
    if source != join_commands(commands).encode() and separator is None:
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
