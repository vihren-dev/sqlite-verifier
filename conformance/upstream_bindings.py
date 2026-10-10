"""Keep observed Tcl scalar values separate from SQLite's authoritative parameter slots."""


from conformance.case_format import Json, cell_wire
from conformance.query_window import tokens


def named_slots(command: str) -> list[str]:
    """Find candidate names while keeping comments and quoted SQL text outside binding evidence.

    Each name starts with `$`, `:` or `@`. A command without these characters
    has no name, so the tokenizer does not run for it. Corpus loading calls this
    for each setup command of each case, and most commands have none of them.
    """
    if not any(prefix in command for prefix in "$:@"):
        return []
    return list(dict.fromkeys(token.text for token in tokens(command) if len(token.text) > 1
                             and token.text != "::" and token.text.startswith(("$", ":", "@"))))


def observation(database: str, sql: str) -> dict[str, Json]:
    """An observation is incomplete until the real trace emits its final marker."""
    return {"database": database, "sql": sql, "slots": named_slots(sql),
            "complete": False, "values": {}, "objects": {}, "refusals": {}}


def capture(value: dict[str, Json], kind: str, args: list[str]) -> None:
    """Decode exact native-width payloads without parsing numeric-looking strings as numbers."""
    if not args or args[0] != value["database"] or value["complete"]:
        raise ValueError("Invalid Tcl parameter observation boundary")
    if kind == "bindings-complete":
        if len(args) != 1:
            raise ValueError("Invalid Tcl parameter completion marker")
        value["complete"] = True
        return
    if len(args) != 7:
        raise ValueError("Invalid Tcl parameter observation")
    _, slot, object_type, has_string, storage, payload, reason = args
    if slot in value["values"] or slot in value["refusals"]:
        raise ValueError("Duplicate Tcl parameter observation")
    if reason:
        value["refusals"][slot] = reason
        return
    data = bytes.fromhex(payload)
    if has_string not in {"0", "1"} or not object_type:
        raise ValueError("Invalid Tcl parameter object evidence")
    if storage in {"integer", "real"} and len(data) == 8:
        cell = (1 if storage == "integer" else 2, int.from_bytes(data, "big", signed=storage == "integer"))
        if storage == "real" and cell[1] & 0x7FF0000000000000 == 0x7FF0000000000000 and cell[1] & 0xFFFFFFFFFFFFF:
            value["refusals"][slot] = "Tcl REAL NaN parameter binding unobservable"
            return
    elif storage in {"text", "blob"}:
        cell = (3 if storage == "text" else 4, data)
    else:
        raise ValueError("Invalid Tcl parameter storage payload")
    value["values"][slot] = cell_wire(cell)
    value["objects"][slot] = {"type": object_type, "hasString": has_string == "1"}


def binding_reasons(command: str, value: Json, helper: str = "eval") -> set[str]:
    """Refuse missing or ambiguous observations instead of adopting Tcl's implicit NULL fallback."""
    slots = value["slots"] if isinstance(value, dict) else named_slots(command)
    reasons: set[str] = set()
    for slot in slots:
        if helper.endswith("eval-script"):
            reasons.add("Tcl parameter row script context: " + slot)
        if not isinstance(value, dict) or not value["complete"]:
            reasons.add("implicit Tcl parameter binding: " + slot)
        elif slot in value["refusals"]:
            reasons.add(value["refusals"][slot] + ": " + slot)
        elif slot not in value["values"]:
            reasons.add("unsupported Tcl parameter variable form: " + slot)
        if slot.startswith("@") and any(other[1:] == slot[1:] and not other.startswith("@") for other in slots):
            reasons.add("mixed Tcl parameter conversion: " + slot[1:])
    return reasons



def recorded_calls(candidate: dict[str, Json]) -> dict[str, Json]:
    """Keep original call conditions and typed values before setup minimization can remove calls."""
    result: dict[str, Json] = {"version": 1}
    for name, prefix in (("setup", "prefix"), ("assertion", "")):
        fields = (["prefix", "prefixHelpers", "prefixCodes", "prefixResults", "prefixPrecisions",
                   "prefixNullValues", "prefixBindingObservations"] if prefix else
                  ["commands", "helpers", "codes", "results", "precisions", "nullValues", "bindingObservations"])
        calls: list[Json] = []
        for command, helper, code, rows, precision, null_value, value in zip(
                *(candidate[field] for field in fields), strict=True):
            if not isinstance(command, str):
                calls.append(None)
                continue
            if not isinstance(value, dict) or not value["complete"] or binding_reasons(command, value, helper):
                raise ValueError("Tcl parameter call evidence is incomplete")
            slots = named_slots(command)
            calls.append({"sql": command, "helper": helper, "code": code, "results": rows,
                          "precision": precision, "nullValue": null_value,
                          "bindings": {slot: value["values"][slot] for slot in slots},
                          "objects": {slot: value["objects"][slot] for slot in slots}})
        result[name] = calls
    return result
