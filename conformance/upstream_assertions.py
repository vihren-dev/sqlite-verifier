"""Consume traced Tcl assertions without interpreting SQL semantics."""

from collections.abc import Iterator
from io import StringIO

from conformance.case_format import Json
from conformance.upstream_selection import implicit_binding_reasons
from conformance.upstream_functions import function_references, schema_function_references
from conformance.query_window import ASCII_UPPER


def iter_assertions(events: str) -> Iterator[dict[str, Json]]:
    """Yield expanded runtime instances without retaining every growing SQL prefix."""
    prefix: list[str | dict[str, Json]] = []
    database, closed = "", False
    codes: list[int] = []
    expected: list[list[str]] = []
    precisions: list[int | None] = []
    helpers: list[str] = []
    excluded: set[str] = set()
    auxiliary_connections: set[str] = set()
    persistent_contexts: set[str] = set()
    generation = 0
    auxiliary_databases: dict[str, tuple[str, int]] = {}
    attached = False
    implicit_bindings: set[str] = set()
    functions: dict[str, set[str]] = {}
    definitions: set[str] = set()
    active: dict[str, Json] | None = None
    for line in StringIO(events):
        fields = [bytes.fromhex(field).decode() for field in line.rstrip("\r\n").split("\t")]
        kind, *args = fields
        if kind == "reset":
            generation += 1
            attached = False
            prefix, codes, excluded, expected = [], [], set(), []
            precisions, definitions = [], set()
            functions.pop("db", None)
            excluded.update(persistent_contexts)
            if auxiliary_connections:
                excluded.add("multiple connections")
            helpers = []
            implicit_bindings.clear()
            database, closed = args[0] if args else "", False
            if active is not None:
                active.update(prefix=[], prefixCodes=[], prefixResults=[], prefixPrecisions=[], prefixHelpers=[], commands=[], codes=[], results=[], precisions=[], helpers=[],
                              implicitBindingReasons=[])
        elif kind == "close":
            functions.pop(args[0], None)
            if args[0] == "db":
                closed = True
                attached = False
                excluded.discard("attached databases")
            else:
                auxiliary_connections.discard(args[0])
                if not auxiliary_connections:
                    excluded.discard("multiple connections")
        elif kind in {"open", "config"}:
            control = None
            if args[0] != "db":
                excluded.add("multiple connections")
                if kind == "open":
                    auxiliary_connections.add(args[0])
                    auxiliary_databases[args[0]] = (args[1], generation)
                else:
                    excluded.add("configuration outside profile: " + " ".join(args[1:]))
            elif kind == "open":
                if closed and database == args[1] and not args[1].endswith(":memory:"):
                    control = {"reopen": True}
                elif database and database != args[1]:
                    excluded.add("database file changed without reset_db")
                elif closed:
                    excluded.add("memory database reopened without reset_db")
                database, closed = args[1], False
            else:
                allowed = {"DEFENSIVE": (1010, "0"), "DQS_DML": (1013, "1"),
                           "DQS_DDL": (1014, "1"), "TRUSTED_SCHEMA": (1017, "1")}
                setting = allowed.get(args[1].removeprefix("SQLITE_DBCONFIG_"))
                if setting and len(args) == 3 and args[2] == setting[1]:
                    control = {"dbConfig": [setting[0], int(args[2])]}
                else:
                    excluded.add("configuration outside profile: " + " ".join(args[1:]))
            if control is not None:
                prefix.append(control)
                codes.append(0)
                expected.append([])
                precisions.append(None)
                helpers.append("eval")
                # A connection operation is a capture boundary, never model SQL.
                if active is not None:
                    active.update(prefix=list(prefix), prefixCodes=list(codes), prefixResults=list(expected), prefixPrecisions=list(precisions), prefixHelpers=list(helpers),
                                  commands=[], codes=[], results=[], precisions=[], helpers=[], implicitBindingReasons=sorted(implicit_bindings))

        elif kind in {"exclude", "persistent-exclude"}:
            excluded.add(args[0])
            if kind == "persistent-exclude" or args[0] == "connection command renamed":
                persistent_contexts.add(args[0])  # Global controls and renamed handles can outlive reset_db.
        elif kind == "function":
            name = args[1].translate(ASCII_UPPER)
            functions.setdefault(args[0], set()).add(name)
            if args[0] == "db" and name in definitions:
                excluded.add("application callback: function")
        elif kind == "databases" and args[0] == "db":
            previous = attached
            attached = bool(set(args[2::3]) - {"main", "temp"})
            if attached:
                excluded.add("attached databases")
            else:
                excluded.discard("attached databases")
                if previous and active is not None:
                    active.update(prefix=list(prefix), prefixCodes=list(codes), prefixResults=list(expected), prefixPrecisions=list(precisions),
                        prefixHelpers=list(helpers), commands=[], codes=[], results=[], precisions=[], helpers=[],
                        implicitBindingReasons=sorted(implicit_bindings))
        elif kind == "begin":
            active = {"id": args[0], "line": int(args[2]) if len(args) > 2 else 0, "expectedTcl": args[1], "prefix": list(prefix),
                      "prefixCodes": list(codes), "prefixResults": list(expected), "prefixPrecisions": list(precisions), "prefixHelpers": list(helpers),
                      "commands": [], "codes": [], "results": [], "precisions": [], "helpers": [], "failed": False,
                      "implicitBindingReasons": sorted(implicit_bindings)}
        elif kind == "sql":
            if function_references(args[1]) & functions.get(args[0], set()):
                excluded.add("application callback: function")
            definitions.update(schema_function_references(args[1]))
            if args[2] != "0" or args[3] not in {"eval", "eval-script", "onecolumn", "exists"}:
                excluded.add("connection or SQL callback context")
            helper = args[3] if args[0] == "db" else "aux:" + args[3]
            if args[0] != "db" and args[0] not in auxiliary_connections:
                excluded.add("unknown auxiliary connection")
            if args[0] != "db" and (auxiliary_databases.get(args[0]) != (database, generation)
                                    or database.endswith(":memory:")):
                excluded.add("auxiliary database differs from primary")
            prefix.append(args[1])
            helpers.append(helper)
            implicit_bindings.update(implicit_binding_reasons(args[1]))
            if active is not None:
                active["commands"].append(args[1])
                active["helpers"].append(helper)
                active["implicitBindingReasons"] = sorted(implicit_bindings)
        elif kind == "result":
            codes.append(int(args[1]))
            expected.append(args[2:])
            precisions.append(None)
            if active is not None:
                active["codes"].append(int(args[1]))
                active["results"].append(args[2:])
                active["precisions"].append(None)
        elif kind == "result-precision":
            precision = int(args[1]) if args[1] else None
            if precisions:
                precisions[-1] = precision
            if active is not None and active["precisions"]:
                active["precisions"][-1] = precision
        elif kind == "failed" and active is not None:
            active["failed"] = True
        elif kind == "end" and active is not None:
            active["exclusions"] = sorted(excluded)
            yield active
            active = None


def assertions(events: str) -> list[dict[str, Json]]:
    """Preserve the list API for callers that need all traced assertions together."""
    return list(iter_assertions(events))


def result_precision_evidence(candidate: dict[str, Json]) -> dict[str, Json]:
    """Summarize observed successful SQL precision, excluding connection control operations."""
    observed: list[int | None] = []
    for commands, codes, precisions in (("prefix", "prefixCodes", "prefixPrecisions"),
                                        ("commands", "codes", "precisions")):
        observed.extend(precision for command, code, precision in
                        zip(candidate[commands], candidate[codes], candidate[precisions], strict=True)
                        if isinstance(command, str) and code == 0)
    return {"values": sorted(set(observed), key=lambda value: -1 if value is None else value),
            "successfulCalls": len(observed)}
