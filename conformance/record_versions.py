"""The native record versions and what each one carries (docs/conformance-format-v2.md).

Version 1 is a migration trace; version 2 adds setup operations; version 3 adds
statement outputs; version 4 adds an explicit execution profile; version 5 has a
profile with measured limits (format 3) and the error phase of each event; version 6
is version 5 from a recorder that runs on after an SQL error, so that each statement
of the migration has one event. Readers ask these sets instead of comparing version
numbers, so a new version changes one place.
"""

WITH_OUTPUTS = (3, 4, 5, 6)
"""Versions whose trace events carry statement outputs and bound parameters."""
PROFILED = (4, 5, 6)
"""Versions with an explicit `profile` record."""
PHASED = (5, 6)
"""Versions whose trace events carry the error `phase`."""
CONTINUING = (6,)
"""Versions whose recorder runs on after an SQL error: one event for each statement, and an
error before the last event."""
