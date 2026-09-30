"""Derive today's structural model input from frozen translator-independent evidence."""

from pathlib import Path
import subprocess

from conformance.case_format import Json, schema_wire, statement_wire, table_wire
from conformance.native_connection import Cell, Row, SOURCE_ID
from conformance.native_metadata import check_inventory, identifier, integer, text
from migration_check.diagnostics import Rejection
from migration_check.sql_model import Table, sql_inputs
from migration_check.sql_tree import parse
from migration_check.translate import commands, starting_schema, statements


def decode_cell(value: Json) -> Cell:
    """Reject malformed native cell transport rather than coercing its payload."""
    if value == "null":
        return 5, None
    if not isinstance(value, dict) or len(value) != 1:
        raise ValueError("Invalid native cell")
    kind, payload = next(iter(value.items()))
    if not isinstance(payload, dict):
        raise ValueError("Invalid native cell payload")
    if kind == "integer" and type(payload.get("value")) is int and -(2**63) <= payload["value"] < 2**63:
        return 1, payload["value"]
    if kind == "real" and isinstance(payload.get("bits"), str) and payload["bits"].isdigit():
        bits = int(payload["bits"])
        if bits < 2**64:
            return 2, bits
    if kind in ("text", "blob") and isinstance(payload.get("bytes"), list):
        data = payload["bytes"]
        if all(type(byte) is int and 0 <= byte < 256 for byte in data):
            return (3 if kind == "text" else 4), bytes(data)
    raise ValueError("Invalid native cell payload")


def decode_rows(rows: list[Json]) -> list[Row]:
    """Restore typed metadata from the frozen JSON encoding."""
    return [tuple(decode_cell(cell) for cell in row) for row in rows]


def schema_sql(observation: dict[str, Json]) -> str:
    """Retain every SQL-declared object; unsupported ones must reach frontend admission."""
    # SQLite inventories sort indexes before tables; replayable DDL needs the dependencies first.
    rows = sorted(decode_rows(observation["schema"]), key=lambda row: text(row[0]) != "table")
    return "\n".join(text(row[3]) + ";" for row in rows if row[3][0] != 5)


def model_case(record: dict[str, Json], parser: Path) -> dict[str, Json]:
    """Re-translate on every replay, preserving frozen native truth as the model grows."""
    if record.get("nativeVersion") not in (1, 2) or record.get("sourceId") != SOURCE_ID:
        raise ValueError("Unsupported native record version or engine identity")
    initial_sql = schema_sql(record["initial"]["visible"])
    schema = starting_schema(parse(parser, initial_sql.encode(), "corpus-schema.sql"))
    script = statements(parse(parser, record["migrationSql"].encode(), "corpus-migration.sql"))
    trace = record["trace"]
    if (len(trace) > len(script) or any(event["primaryCode"] for event in trace[:-1])
            or (not trace or not trace[-1]["primaryCode"]) and len(trace) != len(script)):
        raise ValueError("Native/frontend statement-count mismatch")
    offset = 0
    migration = record["migrationSql"].encode()
    for index, event in enumerate(trace):
        consumed = event["sql"].encode()
        end = offset + len(consumed)
        if (migration[offset:end] != consumed or not offset <= script[index].start < end
                or index + 1 < len(script) and end > script[index + 1].start):
            raise ValueError("Native/frontend statement boundary mismatch")
        offset = end
        if not event["primaryCode"]:
            native_statement = statements(parse(parser, event["sql"].encode(), "native-statement.sql"))
            if [statement_wire(item) for item in native_statement] != [statement_wire(script[index])]:
                raise ValueError("Native/frontend statement alignment mismatch")
    sql_inputs(schema, script)
    cache: dict[str, tuple[Table, ...]] = {initial_sql: schema}

    def tables(observation: dict[str, Json]) -> list[Json]:
        """Cross-check translated declarations against the independently recorded PRAGMAs."""
        sql = schema_sql(observation)
        if sql not in cache:
            cache[sql] = starting_schema(parse(parser, sql.encode(), "corpus-observation.sql"))
        actual = {item["name"].translate(str.maketrans("ABCDEFGHIJKLMNOPQRSTUVWXYZ", "abcdefghijklmnopqrstuvwxyz")): item
                  for item in observation["tables"]}
        if set(actual) != {table.name for table in cache[sql]}:
            raise ValueError("Native table inventory differs")
        result: list[Json] = []
        for table in sorted(cache[sql], key=lambda t: t.name):
            native = actual[table.name]
            check_inventory(table, decode_rows(native["columns"]), [
                (decode_rows([index["entry"]])[0], decode_rows(index["columns"])) for index in native["indexes"]])
            if native["withoutRowid"] or native["kind"] != "table" or native["rowKey"] not in [["rowid"], ["_rowid_"], ["oid"]]:
                raise ValueError("Unexpected row identity in admitted table")
            rows = [(integer(decode_cell(row["identity"][0])), tuple(decode_cell(cell) for cell in row["values"]))
                    for row in native["rows"]]
            result.append([table.name, table_wire(table, rows)])
        return result

    observations: list[Json] = []
    for event in [record["initial"], *record["trace"]]:
        observations.append({"visible": tables(event["visible"]), "persisted": tables(event["persisted"]),
            "transactionOpen": event["transactionOpen"], "primaryCode": event.get("primaryCode", 0),
            "extendedCode": event.get("extendedCode", 0)})
    return {"version": 1, "schemaSql": initial_sql, "migrationSql": record["migrationSql"],
            "schema": [schema_wire(table) for table in schema], "initial": tables(record["initial"]["visible"]),
            "script": [statement_wire(statement) for statement in script], "nativeTrace": observations,
            "requirements": record["requirements"], "provenance": [["fixture", record["name"]], ["sourceId", SOURCE_ID]]}


def prepare(record: dict[str, Json], parser: Path) -> tuple[dict[str, Json] | None, dict[str, Json]]:
    """Unsupported native cases survive replay; corrupt evidence remains a harness error."""
    try:
        return model_case(record, parser), {}
    except Rejection as error:
        native_syntax_error = (error.status == "INPUT_ERROR" and error.source == "corpus-migration.sql"
                               and bool(record.get("trace")) and record["trace"][-1].get("primaryCode") == 1)
        return None, {"verdict": "MODEL_UNSUPPORTED" if error.status == "UNSUPPORTED" or native_syntax_error else "HARNESS_ERROR",
                      "frontendStatus": error.status, "error": str(error)}
    except (ValueError, KeyError, TypeError, IndexError, OSError, RuntimeError, subprocess.SubprocessError) as error:
        return None, {"verdict": "HARNESS_ERROR", "error": str(error)}


def without_trailing_queries(record: dict[str, Json], parser: Path) -> dict[str, Json] | None:
    """Project only successful trailing SELECT/metadata PRAGMAs with unchanged recorded state.

    The original record retains query SQL and exact result rows. This diagnostic does
    not claim query support, or remove setting PRAGMAs and queries between writes.
    """
    if any(event["primaryCode"] for event in record["trace"]):
        return None
    tree = parse(parser, record["migrationSql"].encode(), "corpus-queries.sql")
    try:
        nodes = commands(tree)
    except Rejection as error:
        if error.status == "UNSUPPORTED":
            return None  # EXPLAIN and other wrappers are outside this diagnostic projection.
        raise
    trace = record["trace"]
    if len(nodes) != len(trace) or any(event["primaryCode"] for event in trace):
        return None
    end = len(trace)
    safe_pragmas = {"table_info", "table_xinfo", "index_info", "index_xinfo", "index_list", "foreign_key_list"}
    while end:
        node, after = nodes[end - 1], trace[end - 1]
        children = tree.children(node)
        symbols = [child.symbol for child in children]
        readonly = symbols == ["select"]
        if symbols and symbols[0] == "PRAGMA" and "EQ" not in symbols:
            names = [tree.text(child).lower() for child in children if child.symbol == "nm"]
            readonly = bool(names and names[0] in safe_pragmas)
        before = trace[end - 2] if end > 1 else record["initial"]
        if not readonly or any(after[field] != before[field] for field in ("visible", "persisted", "transactionOpen")):
            break
        end -= 1
    if end == len(trace):
        return None
    return {**record, "migrationSql": "\n".join(event["sql"] for event in trace[:end]), "trace": trace[:end]}
