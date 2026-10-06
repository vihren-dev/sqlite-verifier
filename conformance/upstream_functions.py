"""Conservatively identify SQL dependencies on successfully registered Tcl functions."""

from conformance.query_window import ASCII_UPPER, identifier_name, tokens


def function_references(sql: str) -> set[str]:
    """Keep function calls and SQLite's function-backed operators out of literals/comments."""
    source = tokens(sql)
    names: set[int] = set()
    for index, token in enumerate(source):
        if token.text.translate(ASCII_UPPER) not in {"TABLE", "VIEW", "INTO", "REFERENCES"}:
            continue
        position = index + 1
        while position < len(source) and source[position].text.translate(ASCII_UPPER) in {"IF", "NOT", "EXISTS"}:
            position += 1
        if position + 2 < len(source) and source[position + 1].text == ".":
            position += 2
        names.add(position)
    calls = {identifier_name(token.text).translate(ASCII_UPPER)
             for index, (token, following) in enumerate(zip(source, source[1:]))
             if index not in names and following.text == "("
             and not token.text.startswith(("'", ":", "@", "$", "?"))}
    calls.update(token.text for token in source
                 if token.text.translate(ASCII_UPPER) in {"LIKE", "GLOB", "MATCH", "REGEXP"})
    for index, (token, following) in enumerate(zip(source, source[1:])):
        if token.text == "-" and following.text == ">" and token.end == following.start:
            double_arrow = index + 2 < len(source) and source[index + 2].text == ">" and following.end == source[index + 2].start
            calls.add("->>" if double_arrow else "->")
    return {name.translate(ASCII_UPPER) for name in calls}


def schema_function_references(sql: str) -> set[str]:
    """Retain attempted CREATE/ALTER definitions, including effects before a later batch error."""
    source = tokens(sql)
    return function_references(sql) if any(token.text.translate(ASCII_UPPER) in {"CREATE", "ALTER"} for token in source) else set()
