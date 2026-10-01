"""Conservative Tcl-result cross-check and native-only prefix minimization."""

from conformance.case_format import Json
from conformance.native_record import record_sql
from conformance.native_replay import decode_cell
from conformance.upstream_helpers import command_events


def tcl_values(rows: list[Json], helper: str = "eval") -> list[str]:
    """Compare untyped Tcl values only where byte-to-text conversion is unambiguous."""
    if helper == "exists":
        return ["1" if rows else "0"]
    if helper == "onecolumn":
        rows = [[rows[0][0]]] if rows and rows[0] else []
        if not rows:
            return [""]
    elif helper != "eval":
        raise ValueError("Tcl helper semantics not reproduced")
    result: list[str] = []
    for row in rows:
        for cell in row:
            kind, value = decode_cell(cell)
            if kind == 5:
                result.append("")
            elif kind == 1:
                result.append(str(value))
            elif kind == 3:
                result.append(value.decode("utf-8"))
            else:
                raise ValueError("Tcl extraction check excludes REAL/BLOB result formatting")
    return result


def check_results(record: dict[str, Json], candidate: dict[str, Json]) -> None:
    """Require fresh SQLite execution to reproduce the successful Tcl eval results."""
    if [bool(code) for code in record["setupOutcomes"]] != [bool(code) for code in candidate["prefixCodes"]]:
        raise ValueError("prefix error outcomes differ from Tcl execution")
    helpers = candidate.get("prefixHelpers", ["eval"] * len(candidate["prefixCodes"]))
    for code, rows, expected, error, helper in zip(candidate["prefixCodes"], record["setupResults"], candidate["prefixResults"], record["setupErrors"], helpers, strict=True):
        if code and [error] != expected:
            raise ValueError("prefix error text differs from Tcl execution")
        if not code and tcl_values(rows, helper) != expected:
            raise ValueError("prefix results differ from Tcl execution")
    native_error = bool(record["trace"] and record["trace"][-1]["primaryCode"])
    if native_error != any(candidate["codes"]):
        raise ValueError("assertion error outcome differs from Tcl execution")
    if native_error and [record["trace"][-1]["error"]] != candidate["results"][-1]:
        raise ValueError("assertion error text differs from Tcl execution")
    helpers = candidate.get("helpers", ["eval"] * len(candidate["commands"]))
    for events, helper, expected, code in zip(command_events(record, candidate["commands"]), helpers,
                                             candidate["results"], candidate["codes"], strict=True):
        if bool(events and events[-1]["primaryCode"]) != bool(code):
            raise ValueError("assertion error outcome differs from Tcl execution")
        if not code and tcl_values([row for event in events for row in event["rows"]], helper) != expected:
            raise ValueError("assertion results differ from Tcl execution")


def minimize_prefix(record: dict[str, Json]) -> dict[str, Json]:
    """Delete redundant setup commands only when exact initial state and trace survive."""
    original = list(record["setupCommands"])
    commands = list(original)
    attempts = 0
    # ponytail: cap deletion trials per case; increase only for a dedicated corpus refresh.
    for position in reversed(range(len(commands))):
        if attempts == 32:
            break
        attempts += 1
        trial = commands[:position] + commands[position + 1:]
        try:
            fresh = record_sql(trial, record["migrationSql"], name=record["name"])
        except (ValueError, RuntimeError):
            continue
        if (fresh["initial"], fresh["trace"]) == (record["initial"], record["trace"]):
            commands, record = trial, fresh
    record["minimization"] = {"originalSetupCommands": original, "attempts": attempts,
                              "removed": len(original) - len(commands), "limit": 32}
    return record
