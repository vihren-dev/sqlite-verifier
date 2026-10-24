"""The counters of a native record of version 7 (ADR 0024, D1).

A record of version 7 is a version 6 record that also holds the three counters of the writer
connection just before the migration runs: `changes()`, `total_changes()` and
`last_insert_rowid()`, after the setup (docs/conformance-format-v2.md). The model starts the
run from them. A record of an older version holds none, so its run starts with unknown counters.
"""

from conformance.case_format import Json
from conformance.record_versions import COUNTED

COUNTER_KEYS = ("changes", "totalChanges", "lastInsertRowid")
"""The keys of the counters of a record, in the order of SQLite's three functions."""
INT64_MAX = 2 ** 63 - 1
"""The largest value of a SQLite counter."""


def counters_wire(record: dict[str, Json]) -> dict[str, Json] | None:
    """The counters of the record as the model input, or none for a version without them.

    A version with counters must hold exactly the three keys of `COUNTER_KEYS`, each an integer:
    the two counts are not negative, and each value fits in 64 bits. Any other form raises a
    `ValueError`, because the evidence is corrupt and the model must not guess a start. A version
    without counters must not hold the field."""
    counters = record.get("counters")
    if record.get("nativeVersion") not in COUNTED:
        if counters is not None:
            raise ValueError(
                f"The native record has nativeVersion {record.get('nativeVersion')} and the field counters, "
                "but only version 7 holds counters; record the case again with the current recorder")
        return None
    if not isinstance(counters, dict) or set(counters) != set(COUNTER_KEYS):
        raise ValueError(
            f"The counters of a native record of version 7 must be an object with exactly the keys "
            f"{', '.join(COUNTER_KEYS)}; record the case again with the current recorder")
    for key, value in counters.items():
        least = -INT64_MAX - 1 if key == "lastInsertRowid" else 0
        if type(value) is not int or not least <= value <= INT64_MAX:
            raise ValueError(
                f"The counter {key} of the native record must be an integer from {least} to {INT64_MAX}; "
                "record the case again with the current recorder")
    return {key: counters[key] for key in COUNTER_KEYS}


def counters_input(record: dict[str, Json]) -> dict[str, Json]:
    """The part of a model input that holds the counters: the field `counters` for a version with
    counters, and nothing for another version, so that the inputs of older versions keep their
    form (`counters_wire` checks the record)."""
    counters = counters_wire(record)
    return {} if counters is None else {"counters": counters}
