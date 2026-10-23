"""Derive the version 5 model case from frozen translator-independent evidence."""

from conformance.record_parser import NO_PARSER_REASON, record_parser

from conformance.case_format import CASE_VERSION, UNIX_EPOCH_JULIAN_MILLISECONDS, Json, row_wire
from conformance.profile_scope import foreign_key_scope, modeled_profile
from conformance.record_versions import CONTINUING, PROFILED, WITH_OUTPUTS
from conformance.native_connection import SOURCE_ID
from conformance import native_bindings
from conformance.native_call_recording import validate_recording
from conformance.native_metadata import integer, native_table, text
from conformance.sql_text import Translator
from belay.sqlite.errors import NoParserForDialect, ParserResourceLimit, SqlError



def schema_sql(observation: dict[str, Json]) -> str:
    """Retain every SQL-declared object; unsupported ones must reach frontend admission."""
    # SQLite inventories sort indexes before tables; replayable DDL needs the dependencies first.
    rows = sorted(native_bindings.decode_rows(observation["schema"]), key=lambda row: text(row[0]) != "table")
    return "\n".join(text(row[3]) + ";" for row in rows if row[3][0] != 5)


def output_wire(event: dict[str, Json]) -> dict[str, Json]:
    """Check acquisition shape and typed payloads before frontend admission can hide corruption."""
    columns = event["columns"]
    if (not isinstance(columns, list) or any(not isinstance(name, str) for name in columns)
            or type(event["columnCount"]) is not int or event["columnCount"] != len(columns)):
        raise ValueError("Invalid native output shape")
    rows = native_bindings.decode_rows(event["rows"])
    native_bindings.decode_rows([event["parameters"]])
    if any(len(row) != len(columns) for row in rows):
        raise ValueError("Invalid native output row width")
    changes = event["changes"]
    if changes is not None and (type(changes) is not int or changes < 0):
        raise ValueError("Invalid native direct change count")
    groups = event.get("groups")
    if groups is not None:
        if not isinstance(groups, list):
            raise ValueError("Invalid native tie groups")
        position = 0
        for index, group in enumerate(groups):
            eligible = native_bindings.decode_rows(group["rows"])
            count = group["count"]
            if 0 < index < len(groups) - 1 and count != len(eligible):
                raise ValueError("Only boundary tie groups may be partial")
            if (type(count) is not int or not 0 < count <= len(eligible)
                    or any(len(row) != len(columns) for row in eligible)
                    or len(rows[position:position + count]) != count):
                raise ValueError("Invalid native tie group shape/count")
            for row in rows[position:position + count]:
                if row not in eligible:
                    raise ValueError("Native result does not fit its tie groups")
                eligible.remove(row)
            position += count
        if position != len(rows):
            raise ValueError("Native tie group window size differs")
    return {"result": {"columns": columns, "rows": event["rows"], "changes": changes}, "groups": groups}


HIDDEN_ROWID_REASON = "column names rowid, _rowid_ and oid are not modeled; rename the column"
"""The reason of a case whose table hides its rowid, as the model's restriction of these names says."""


class HiddenRowid(ValueError):
    """A recorded table whose columns take every rowid name, so SQLite's rowid has none and the
    recorder keys the rows by all columns; the model refuses the names, so the case is out of scope."""


def native_tables(observation: dict[str, Json]) -> list[Json]:
    """Decode every recorded table with its PRAGMA metadata and rows; Lean compares them. A
    `WITHOUT ROWID` table has no rowid: its rows get the rowid 0, and Lean compares them by
    their cells in key order."""
    result: list[Json] = []
    for item in observation["tables"]:
        without_rowid = bool(item["withoutRowid"])
        if item["kind"] != "table":
            raise ValueError("Unexpected row identity in an observed table")
        if not without_rowid and item["rowKey"] not in [["rowid"], ["_rowid_"], ["oid"]]:
            raise HiddenRowid(f"table {item['name']} hides its rowid behind its columns")
        indexes = [(native_bindings.decode_rows([index["entry"]])[0], native_bindings.decode_rows(index["columns"]))
                   for index in item["indexes"]]
        rows = [row_wire(0 if without_rowid else integer(native_bindings.decode_cell(row["identity"][0])),
                         tuple(native_bindings.decode_cell(cell) for cell in row["values"])) for row in item["rows"]]
        result.append(native_table(item["name"], native_bindings.decode_rows(item["columns"]), indexes, rows,
                                   without_rowid=without_rowid))
    return result


def model_case(record: dict[str, Json], translator: Translator) -> dict[str, Json]:
    """Map the SQL to statement syntax again on every replay, preserving frozen native truth.

    The case's SQL is parsed with the dialect of its recorded profile before the model
    check, so every case is parser evidence, also when the model does not support it.
    Lean resolves the syntax and compares the catalog and rows after each statement.
    """
    validate_recording(record)
    if (record.get("nativeVersion") not in (1, 2, 3, *PROFILED)
            or record["nativeVersion"] not in PROFILED and record.get("sourceId") != SOURCE_ID):
        raise ValueError("Unsupported native record version or engine identity")
    outputs = [output_wire(event) for event in record["trace"]] if record["nativeVersion"] in WITH_OUTPUTS else None
    parser = record_parser(translator, record)
    initial_sql = schema_sql(record["initial"]["visible"])
    schema_text = parser.translate(initial_sql.encode(), "corpus-schema.sql").parsed()
    migration_text = parser.translate(record["migrationSql"].encode(), "corpus-migration.sql").parsed()
    for event in record["trace"]:
        if "sql" in event and not event["primaryCode"]:
            parser.translate(event["sql"].encode(), "native-statement.sql").parsed()
    profile = modeled_profile(record)
    schema = schema_text.statements()
    script = migration_text.statements()
    foreign_key_scope(record, [*schema, *script])
    trace = record["trace"]
    continues = record["nativeVersion"] in CONTINUING
    # A recorder that runs on gives one event for each statement; one that stops gives one for
    # each statement up to and including the first error.
    if (len(trace) != len(script) if continues else
            len(trace) > len(script) or any(event["primaryCode"] for event in trace[:-1])
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
    observations: list[Json] = []
    for event in [record["initial"], *record["trace"]]:
        observations.append({"visible": native_tables(event["visible"]), "persisted": native_tables(event["persisted"]),
            "transactionOpen": event["transactionOpen"], "primaryCode": event.get("primaryCode", 0),
            "extendedCode": event.get("extendedCode", 0), "phase": event.get("phase")})
    return {"version": CASE_VERSION, "profile": profile,
            "schemaSql": initial_sql, "migrationSql": record["migrationSql"],
            "schema": [item.value for item in schema], "script": [item.value for item in script],
            "initial": observations[0]["visible"], "nativeTrace": observations,
            "requirements": record["requirements"], "provenance": [["fixture", record["name"]], ["sourceId", str(profile["sourceId"])]],
            "outputs": outputs, "parameters": [event["parameters"] for event in trace] if outputs is not None else [],
            "clocks": [event["clockUnixMilliseconds"] + UNIX_EPOCH_JULIAN_MILLISECONDS for event in trace]
            if trace and all("clockUnixMilliseconds" in event for event in trace) else [],
            "continues": continues}


def prepare(record: dict[str, Json], translator: Translator) -> tuple[dict[str, Json] | None, dict[str, Json]]:
    """Unsupported native cases survive replay; corrupt evidence remains a harness error."""
    try:
        return model_case(record, translator), {}
    except NoParserForDialect as error:
        return None, {"verdict": "MODEL_UNSUPPORTED", "frontendStatus": error.status,
                      "reason": NO_PARSER_REASON, "error": str(error)}
    except SqlError as error:
        # A migration that native SQLite also refused (SQLITE_ERROR) is outside the model's scope,
        # also when it exceeds the parser's size limits before the parser reaches its error.
        native_syntax_error = ((error.status == "INPUT_ERROR" or isinstance(error, ParserResourceLimit))
                               and error.source == "corpus-migration.sql"
                               and bool(record.get("trace")) and record["trace"][-1].get("primaryCode") == 1)
        return None, {"verdict": "MODEL_UNSUPPORTED" if error.status == "UNSUPPORTED" or native_syntax_error else "HARNESS_ERROR",
                      "frontendStatus": error.status, "error": str(error)}
    except HiddenRowid as error:
        return None, {"verdict": "MODEL_UNSUPPORTED", "reason": HIDDEN_ROWID_REASON, "error": str(error)}
    except (ValueError, KeyError, TypeError, IndexError, OSError, RuntimeError) as error:
        return None, {"verdict": "HARNESS_ERROR", "error": str(error)}


def without_trailing_queries(record: dict[str, Json], translator: Translator) -> dict[str, Json] | None:
    """Project only successful trailing SELECT/metadata PRAGMAs with unchanged recorded state.

    The original record retains query SQL and exact result rows. This diagnostic does
    not claim query support, or remove setting PRAGMAs and queries between writes.
    """
    if any(event["primaryCode"] for event in record["trace"]):
        return None
    nodes = record_parser(translator, record).translate(record["migrationSql"].encode(), "corpus-queries.sql").commands()
    if nodes is None:
        return None  # EXPLAIN and other wrappers are outside this diagnostic projection.
    trace = record["trace"]
    if len(nodes) != len(trace) or any(event["primaryCode"] for event in trace):
        return None
    end = len(trace)
    safe_pragmas = {"table_info", "table_xinfo", "index_info", "index_xinfo", "index_list", "foreign_key_list"}
    while end:
        node, after = nodes[end - 1], trace[end - 1]
        symbols = list(node.symbols)
        readonly = symbols == ["select"]
        if symbols and symbols[0] == "PRAGMA" and "EQ" not in symbols:
            names = [name.lower() for name in node.names]
            readonly = bool(names and names[0] in safe_pragmas)
        before = trace[end - 2] if end > 1 else record["initial"]
        if not readonly or any(after[field] != before[field] for field in ("visible", "persisted", "transactionOpen")):
            break
        end -= 1
    if end == len(trace):
        return None
    return {**record, "migrationSql": "\n".join(event["sql"] for event in trace[:end]), "trace": trace[:end]}
