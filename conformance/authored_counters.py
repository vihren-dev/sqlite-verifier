"""Authored cases of the connection counters (ADR 0024, slice 1; outcome 9 and its tests).

The cases read `changes()`, `total_changes()` and `last_insert_rowid()` after each kind of
statement that the ADR's table of facts names, inside the statements that the model describes, and
in the schema positions that refuse them (`conformance.authored_counter_writes`,
`conformance.authored_counter_reads`, `conformance.authored_counter_failures`). Each record is a
version 7 record (`record_sql` with `counters`): it runs on after an error and holds the counters of
the writer connection at the start of the migration. Native SQLite is the only source of outcomes.
"""

from conformance import authored_counter_failures, authored_counter_reads, authored_counter_writes
from conformance import authored_foreign_keys, authored_resolution
from conformance.authored_queries import QueryCase
from conformance.case_format import Json
from conformance.native_record import record_sql

FOREIGN_KEYS = frozenset({
    "insert-or-replace-with-foreign-keys", "foreign-key-actions-count", "drop-table-with-foreign-key-actions",
    "drop-table-fails-after-actions", "drop-table-without-references", "missing-parent-at-the-end-of-the-statement",
    "restrict-action-fails-during-replace"})
"""The cases that run under the profile with foreign keys on."""
REOPENED = frozenset({"new-connection"})
"""The cases whose setup ends with a reopen of the writer connection, so that the migration starts
on a new connection."""


def definitions() -> list[QueryCase]:
    """All cases of the connection counters, in the order of their modules."""
    return [*authored_counter_writes.definitions(), *authored_counter_reads.definitions(),
            *authored_counter_failures.definitions()]


def records(cases: list[QueryCase] | None = None) -> list[dict[str, Json]]:
    """Record each case natively as a version 7 record, in the part `counters` with its features:
    under SQLite's default measured profile, or under the profile with foreign keys on for the
    cases in `FOREIGN_KEYS`. A case in `REOPENED` reopens the writer connection after its setup."""
    selected = definitions() if cases is None else cases
    plain, keys = authored_resolution.profile(()), authored_foreign_keys.profile()
    return [{**record_sql([case.setup, {"reopen": True}] if case.name in REOPENED else case.setup, case.sql,
                          name=case.name, requirements=list(case.requirements), outputs=True,
                          profile=keys if case.name in FOREIGN_KEYS else plain, run_on=True, counters=True),
             "part": "counters", "features": list(case.features)}
            for case in selected]
