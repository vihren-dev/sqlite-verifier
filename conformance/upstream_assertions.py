"""Consume traced Tcl assertions without interpreting SQL semantics."""

from conformance.case_format import Json


def assertions(events: str) -> list[dict[str, Json]]:
    """Consume runtime events, retaining expanded test instances and reset-scoped prefixes."""
    prefix: list[str | dict[str, Json]] = []
    database, closed = "", False
    codes: list[int] = []
    expected: list[list[str]] = []
    helpers: list[str] = []
    excluded: set[str] = set()
    auxiliary_connections: set[str] = set()
    persistent_contexts: set[str] = set()
    generation = 0
    auxiliary_databases: dict[str, tuple[str, int]] = {}
    rows: list[dict[str, Json]] = []
    active: dict[str, Json] | None = None
    for line in events.splitlines():
        fields = [bytes.fromhex(field).decode() for field in line.split("\t")]
        kind, *args = fields
        if kind == "reset":
            generation += 1
            prefix, codes, excluded, expected = [], [], set(), []
            excluded.update(persistent_contexts)
            if auxiliary_connections:
                excluded.add("multiple connections")
            helpers = []
            database, closed = args[0] if args else "", False
            if active is not None:
                active.update(prefix=[], prefixCodes=[], prefixResults=[], prefixHelpers=[], commands=[], codes=[], results=[], helpers=[])
        elif kind == "close":
            if args[0] == "db":
                closed = True
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
                helpers.append("eval")
                # A connection operation is a capture boundary, never model SQL.
                if active is not None:
                    active.update(prefix=list(prefix), prefixCodes=list(codes), prefixResults=list(expected), prefixHelpers=list(helpers),
                                  commands=[], codes=[], results=[], helpers=[])

        elif kind == "exclude":
            excluded.add(args[0])
            if args[0] == "connection command renamed":
                persistent_contexts.add(args[0])  # reset_db need not close a renamed handle.
        elif kind == "begin":
            active = {"id": args[0], "line": int(args[2]) if len(args) > 2 else 0, "expectedTcl": args[1], "prefix": list(prefix),
                      "prefixCodes": list(codes), "prefixResults": list(expected), "prefixHelpers": list(helpers),
                      "commands": [], "codes": [], "results": [], "helpers": [], "failed": False}
        elif kind == "sql":
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
            if active is not None:
                active["commands"].append(args[1])
                active["helpers"].append(helper)
        elif kind == "result":
            codes.append(int(args[1]))
            expected.append(args[2:])
            if active is not None:
                active["codes"].append(int(args[1]))
                active["results"].append(args[2:])
        elif kind == "failed" and active is not None:
            active["failed"] = True
        elif kind == "end" and active is not None:
            active["exclusions"] = sorted(excluded)
            rows.append(active)
            active = None
    return rows
