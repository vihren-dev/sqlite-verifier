"""Native tie comparison and complete boundary groups for ordered query windows."""

from conformance.case_format import Json
from conformance.native_connection import Connection, Row
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
