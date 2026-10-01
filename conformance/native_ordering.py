"""Native tie comparison and complete boundary groups for ordered query windows."""

from conformance.case_format import Json
from conformance.native_connection import Cell, Connection, Row
from conformance.native_statements import wire_rows


def tie_groups(connection: Connection, rows: list[Row], columns: tuple[int, ...],
               collations: tuple[str, ...], *, offset: int = 0,
               limit: int | None = None) -> list[dict[str, Json]]:
    """Group already engine-ordered rows using SQLite equality without affinity coercion.

    The caller supplies resolved projected sort keys and their native collations.
    Full rows must come from the same-state read-only uncut query. Keep both cut
    boundaries complete; a group cut at both ends appears once. Direction and NULL
    placement are already reflected in the engine's row order.
    """
    if len(columns) != len(collations) or any(type(index) is not int or index < 0 for index in columns):
        raise ValueError("Invalid resolved sort keys")
    if any(collation not in {"BINARY", "NOCASE", "RTRIM"} for collation in collations):
        raise ValueError("tie structure not observable: unresolved collation")
    if any(any(index >= len(row) for index in columns) for row in rows):
        raise ValueError("Sort key is not projected")
    if type(offset) is not int or limit is not None and type(limit) is not int:
        raise ValueError("Window bounds must be resolved SQLite integers")
    start = max(0, offset)
    end = len(rows) if limit is None or limit < 0 else start + limit
    predicate = " AND ".join(f"(? COLLATE {collation}) IS (? COLLATE {collation})"
                             for collation in collations) or "1"
    groups: list[list[Row]] = []
    # ponytail: one bounded native comparison per adjacent row; batch if replay timing requires it.
    for row in rows:
        same = False
        if groups:
            previous = groups[-1][-1]
            bound = tuple(cell for index in columns for cell in (previous[index], row[index]))
            same = connection.query_result(f"SELECT {predicate};", bound, readonly=True).rows == [((1, 1),)]
        if same:
            groups[-1].append(row)
        else:
            groups.append([row])
    result: list[dict[str, Json]] = []
    position = 0
    for group in groups:
        count = max(0, min(end, position + len(group)) - max(start, position))
        if count:
            result.append({"rows": wire_rows(group), "count": count})
        position += len(group)
    return result


def query_groups(connection: Connection, sql: str, parameters: tuple[Cell, ...], columns: list[str],
                 rows: list[Row]) -> list[dict[str, Json]] | None:
    """Rank projected keys outside the original SELECT, preserving DISTINCT and grouping."""
    from conformance.query_window import ASCII_UPPER, projected_order, tokens, window
    if not tokens(sql) or tokens(sql)[0].text.translate(ASCII_UPPER) not in {"SELECT", "WITH"}:
        return None
    if any(token.depth > 0 and token.text.translate(ASCII_UPPER) == "LIMIT" for token in tokens(sql)):
        raise ValueError("tie structure not observable: nested window")
    uncut, ordering, limit, offset = window(sql)
    has_limit = any(token.depth == 0 and token.text.translate(ASCII_UPPER) == "LIMIT" for token in tokens(sql))
    if not ordering and not has_limit:
        return None
    keys = projected_order(ordering, columns, uncut) if ordering else ""
    guard = f" WHERE ?{len(parameters)} IS ?{len(parameters)}" if parameters else ""
    bounds = connection.query_result(f"SELECT CAST(({limit}) AS INTEGER), CAST(({offset}) AS INTEGER){guard};",
                                     parameters, readonly=True).rows[0]
    count, start = bounds[0][1], bounds[1][1]
    if not isinstance(count, int) or not isinstance(start, int):
        raise ValueError("tie structure not observable: unresolved window")
    order = "ORDER BY " + keys if keys else ""
    ranked = connection.query_result(f"SELECT q.*, dense_rank() OVER ({order}) FROM ({uncut}) AS q{guard} {order};",
                                     parameters, readonly=True)
    if list(ranked.columns[:-1]) != columns:
        raise ValueError("tie structure not observable: probe changed result shape")
    groups = tie_groups(connection, ranked.rows, (len(columns),), ("BINARY",), offset=start, limit=count)
    for group in groups:
        group["rows"] = [row[:-1] for row in group["rows"]]
    observed = wire_rows(rows)
    position = 0
    for group in groups:
        available = list(group["rows"])
        for row in observed[position:position + group["count"]]:
            if row not in available:
                raise ValueError("tie structure not observable: probe does not reproduce native rows")
            available.remove(row)
        position += group["count"]
    if position != len(observed):
        raise ValueError("tie structure not observable: probe changed window size")
    return groups


def check_write_window(connection: Connection, sql: str, parameters: tuple[Cell, ...]) -> None:
    """Check a limited INSERT source before writing; other hidden contexts stay excluded."""
    from conformance.query_window import ASCII_UPPER, numbered_parameters, tokens
    sql = numbered_parameters(sql).rstrip().removesuffix(";")
    source = tokens(sql)
    if not any(token.text.translate(ASCII_UPPER) == "LIMIT" for token in source):
        return
    select = next((token for token in source if token.depth == 0 and token.text.translate(ASCII_UPPER) == "SELECT"), None)
    if not source or source[0].text.translate(ASCII_UPPER) != "INSERT" or select is None:
        raise ValueError("tie structure not observable: limited write source")
    end = next((token.start for token, following in zip(source, source[1:])
                if token.start > select.start and token.depth == 0 and
                (token.text.translate(ASCII_UPPER) == "RETURNING" or
                 token.text.translate(ASCII_UPPER) == "ON" and following.text.translate(ASCII_UPPER) == "CONFLICT")), len(sql))
    query = sql[select.start:end]
    guard = f" WHERE ?{len(parameters)} IS ?{len(parameters)}" if parameters else ""
    selected = connection.query_result(f"SELECT * FROM ({query}){guard};", parameters, readonly=True)
    groups = query_groups(connection, query, parameters, list(selected.columns), selected.rows)
    if groups is not None and any(group["count"] != len(group["rows"]) for group in groups):
        raise ValueError("unspecified choice inside a write")
