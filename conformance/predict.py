"""`python -m conformance.predict --runtime ROOT`: the subject's predict command (ADR 0011).

The judge (`judge/`) writes one input per line: what a frozen record holds before its
migration runs. This command maps each input to statement syntax with the text package's
translation program (`conformance.sql_text`), runs the model's `conformance-runner --predict` once
over all inputs, which resolves and runs them in Lean, and writes one prediction per line in the
recorded form (`conformance.predict_render`). It never sees an observation that SQLite made after
the start, and it decides nothing about agreement.
"""

import argparse
from collections.abc import Sequence
import json
from pathlib import Path
import subprocess
import sys

from belay.sqlite.errors import NoParserForDialect, ParserResourceLimit, SqlError
from belay.sqlite.located import Located
from conformance import native_bindings
from conformance.case_format import UNIX_EPOCH_JULIAN_MILLISECONDS, Json, cell_wire, row_wire
from conformance.predict_render import output_record, view_record
from conformance.profile_scope import foreign_key_scope, modeled_profile
from conformance.record_parser import NO_PARSER_REASON, record_parser
from conformance.record_counters import counters_input
from conformance.record_versions import CONTINUING
from conformance.sql_text import Translator, runtime_translator

RUNNER_TIMEOUT_SECONDS = 600
"""One model run over all inputs of a corpus."""


def row_id(identity: list[Json]) -> int:
    """The rowid of a recorded row identity, or 0 for the primary-key cells of a `WITHOUT ROWID`
    table, whose rows the model numbers itself (`databaseOf`)."""
    cell = native_bindings.decode_cell(identity[0])[1] if len(identity) == 1 else None
    return cell if type(cell) is int else 0


def initial_rows(rows: dict[str, Json]) -> list[Json]:
    """The starting rows of each table by name, as stored rows with their row ids."""
    return [{"name": name, "rows": [row_wire(row_id(row["identity"]),
                                             tuple(native_bindings.decode_cell(cell) for cell in row["values"]))
                                    for row in table_rows]}
            for name, table_rows in sorted(rows.items())]



def julian_clocks(given: dict[str, Json]) -> list[int]:
    """The clock value of each executed statement in Julian-day milliseconds, from the Unix
    milliseconds that the judge supplies; empty when it supplies none."""
    clocks = given.get("clockUnixMilliseconds") or []
    if not isinstance(clocks, list) or not all(type(clock) is int for clock in clocks):
        raise ValueError("clockUnixMilliseconds must be a list of integers")
    return [clock + UNIX_EPOCH_JULIAN_MILLISECONDS for clock in clocks]


def bound_values(given: dict[str, Json]) -> list[Json]:
    """The values bound to the parameters of each executed statement, as typed cells; empty when
    the judge supplies none. Statement i of the script gets list i."""
    parameters = given.get("parameters") or []
    if not isinstance(parameters, list) or not all(isinstance(values, list) for values in parameters):
        raise ValueError("parameters must be a list of lists of cells")
    return [[cell_wire(native_bindings.decode_cell(cell)) for cell in values] for values in parameters]


def mapped(given: dict[str, Json], translator: Translator) -> tuple[dict[str, Json], list[Located]]:
    """The model input of one case and its statements; frontend refusals, execution
    settings that the model does not implement, and a foreign key in a record without a
    profile raise `SqlError` (`profile_scope`). The input of a record whose recorder ran on
    after an error (`CONTINUING`) asks for the model's run that continues."""
    profile = modeled_profile(given)
    parser = record_parser(translator, given)
    schema = parser.translate(given["initialSchemaSql"].encode(), "corpus-schema.sql").statements()
    script = parser.translate(given["migrationSql"].encode(), "corpus-migration.sql").statements()
    foreign_key_scope(given, [*schema, *script])
    return {"profile": profile, "schema": [item.value for item in schema], "script": [item.value for item in script],
            "initial": initial_rows(given["initialRows"]), "clocks": julian_clocks(given),
            "parameters": bound_values(given), "continues": given.get("nativeVersion") in CONTINUING,
            **counters_input(given)}, script


def refusal(given: dict[str, Json], error: Exception) -> dict[str, Json]:
    """The prediction of a case that the frontend refuses: out of scope, or an input error."""
    if isinstance(error, NoParserForDialect):
        return {"name": given["name"], "status": "unsupported", "reason": NO_PARSER_REASON}
    if isinstance(error, SqlError) and error.status == "UNSUPPORTED":
        return {"name": given["name"], "status": "unsupported", "reason": str(error)}
    migration = isinstance(error, SqlError) and error.source == "corpus-migration.sql"
    if migration and (error.status == "INPUT_ERROR" or isinstance(error, ParserResourceLimit)):
        return {"name": given["name"], "status": "inputError", "reason": str(error)}
    return {"name": given["name"], "status": "error", "reason": f"{type(error).__name__}: {error}"}


def prediction(given: dict[str, Json], script: list[Located], model: dict[str, Json]) -> dict[str, Json]:
    """One prediction in the recorded form."""
    if "error" in model:
        return {"name": given["name"], "status": "error", "reason": str(model["error"])}
    if "restricted" in model:
        return {"name": given["name"], "status": "unsupported", "reason": str(model["restricted"]),
                "restriction": str(model["restriction"])}
    steps = [{"visible": view_record(step["visible"]), "persisted": view_record(step["persisted"]),
              "transactionOpen": step["transactionOpen"], "primaryCode": step["primaryCode"],
              "phase": step["phase"], **({"start": script[index - 1].start} if index else {})}
             for index, step in enumerate(model["steps"])]
    return {"name": given["name"], "status": "predicted", "supported": bool(model["supported"]),
            "steps": steps, "outputs": [output_record(output) for output in model["outputs"]]}


def main(arguments: Sequence[str]) -> int:
    """Predict every input on standard input, in order, one line each."""
    parser = argparse.ArgumentParser(prog="python -m conformance.predict", description=main.__doc__)
    parser.add_argument("--runtime", type=Path, required=True, help="conformance runtime root")
    options = parser.parse_args(arguments)
    translator = runtime_translator(options.runtime)
    inputs = [json.loads(line) for line in sys.stdin if line.strip()]
    results: list[dict[str, Json] | None] = []
    pending: list[tuple[int, list[Located], dict[str, Json]]] = []
    for index, given in enumerate(inputs):
        try:
            model_input, script = mapped(given, translator)
            pending.append((index, script, model_input))
            results.append(None)
        except (SqlError, NoParserForDialect, ValueError, KeyError, TypeError, IndexError) as error:
            results.append(refusal(given, error))
    runner = options.runtime / ".lake/build/bin/conformance-runner"
    answered = subprocess.run([str(runner), "--predict"], input="".join(json.dumps(item[2]) + "\n" for item in pending),
                              capture_output=True, text=True, timeout=RUNNER_TIMEOUT_SECONDS, check=False)
    if answered.returncode:
        print(f"predict: {runner} exited with {answered.returncode}: {answered.stderr.strip()}. Read the "
              f"runner's message above, rebuild the conformance runtime (nix-build build-support/default.nix "
              f"-A conformance), and run the command again.", file=sys.stderr)
        return 1
    for (index, script, _), line in zip(pending, answered.stdout.splitlines(), strict=True):
        results[index] = prediction(inputs[index], script, json.loads(line))
    for result in results:
        print(json.dumps(result, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
