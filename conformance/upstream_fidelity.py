"""Conservative Tcl-result cross-check and native-only prefix minimization."""

from conformance.case_format import Json
from conformance.native_record import record_sql
from conformance.native_replay import decode_cell, decode_rows
from conformance.execution_profile import recorded_profile
from conformance.upstream_helpers import command_events
from conformance.query_window import ASCII_UPPER, identifier_name, tokens


def fidelity_difference(reason: str, *, sql: str = "", native_error: str = "",
                        actual: list[str] | None = None, expected: list[str] | None = None) -> ValueError:
    """Name proven environment/build differences without changing native observations."""
    cause = ""
    if native_error == "no such module: echo":
        cause = "testfixture-only virtual-table module: echo"
    words = [identifier_name(token.text).translate(ASCII_UPPER) for token in tokens(sql)
             if token.text != ";"]
    pragma = words[-1] if words[:1] == ["PRAGMA"] and (
        len(words) == 2 or len(words) == 4 and words[2] == ".") else ""
    if pragma == "LOCK_STATUS" and actual == [] and expected:
        cause = "testfixture-only lock metadata: PRAGMA lock_status"
    if (pragma == "DATABASE_LIST" and actual is not None and expected is not None
            and len(actual) == len(expected) and len(actual) % 3 == 0
            and actual[::3] == expected[::3] and actual[1::3] == expected[1::3]
            and actual[2::3] != expected[2::3]):
        cause = "filesystem path observation: PRAGMA database_list"
    return ValueError(reason + (": " + cause if cause else ""))


def tcl_values(rows: list[Json], helper: str = "eval") -> list[str]:
    """Compare untyped Tcl values only where byte-to-text conversion is unambiguous."""
    helper = helper.removeprefix("aux:")
    if helper == "eval-script":
        return []  # Tcl eval with a pure row body returns the empty result.
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
    if len(record["setupOutcomes"]) != len(candidate["prefixCodes"]):
        raise ValueError("prefix error outcomes differ from Tcl execution")
    for index, (native, tcl) in enumerate(zip(record["setupOutcomes"], candidate["prefixCodes"], strict=True)):
        if bool(native) != bool(tcl):
            raise fidelity_difference("prefix error outcomes differ from Tcl execution",
                                      native_error=record["setupErrors"][index])
    helpers = candidate.get("prefixHelpers", ["eval"] * len(candidate["prefixCodes"]))
    for index, (code, rows, expected, error, helper) in enumerate(zip(candidate["prefixCodes"], record["setupResults"], candidate["prefixResults"], record["setupErrors"], helpers, strict=True)):
        if code and [error] != expected:
            raise ValueError("prefix error text differs from Tcl execution")
        if not code:
            actual = tcl_values(rows, helper)
            if actual != expected:
                command = record["setupCommands"][index]
                raise fidelity_difference("prefix results differ from Tcl execution",
                    sql=command if isinstance(command, str) else "", actual=actual, expected=expected)
    native_error = bool(record["trace"] and record["trace"][-1]["primaryCode"])
    if native_error != any(candidate["codes"]):
        raise fidelity_difference("assertion error outcome differs from Tcl execution",
            native_error=record["trace"][-1]["error"] if record["trace"] else "")
    if native_error and [record["trace"][-1]["error"]] != candidate["results"][-1]:
        raise ValueError("assertion error text differs from Tcl execution")
    helpers = candidate.get("helpers", ["eval"] * len(candidate["commands"]))
    for events, helper, expected, code in zip(command_events(record, candidate["commands"]), helpers,
                                             candidate["results"], candidate["codes"], strict=True):
        if bool(events and events[-1]["primaryCode"]) != bool(code):
            raise ValueError("assertion error outcome differs from Tcl execution")
        if not code:
            actual = tcl_values([row for event in events for row in event["rows"]], helper)
            if actual != expected:
                raise fidelity_difference("assertion results differ from Tcl execution",
                    sql="".join(event["sql"] for event in events), actual=actual, expected=expected)


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
            outputs = record["nativeVersion"] in (3, 4)
            profile = recorded_profile(record) if record["nativeVersion"] == 4 else None
            fresh = record_sql(trial, record["migrationSql"], name=record["name"],
                requirements=record["requirements"], outputs=outputs,
                parameters=decode_rows([event["parameters"] for event in record["trace"]]) if outputs else None,
                profile=profile, setup_clock=record.get("setupClockUnixMilliseconds"),
                clock_values=[event["clockUnixMilliseconds"] for event in record["trace"]]
                    if profile is not None and profile.clock == "unix-milliseconds-v1" else None)
        except (ValueError, RuntimeError):
            continue
        if (fresh["initial"], fresh["trace"]) == (record["initial"], record["trace"]):
            commands, record = trial, fresh
    record["minimization"] = {"originalSetupCommands": original, "attempts": attempts,
                              "removed": len(original) - len(commands), "limit": 32}
    return record
