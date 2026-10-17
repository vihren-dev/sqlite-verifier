"""The execution profiles that the model implements, and the profile that Lean resolves under.

A native record of version 4 or 5 names its execution profile. Name resolution reads
the release, the build, the limits and the double-quoted-string settings (ADR 0008,
"Execution profile"); the execution semantics takes the clock value of each statement
as an input, so it implements a controlled clock, and it implements only SQLite's
defaults for the other settings. A record whose profile changes such a setting stays out of the
model's scope, with the setting named, so that the model never predicts behavior it
does not implement. Records before version 4 have no profile: their recorder used
the pinned build with its documented default limits.
"""

from collections.abc import Mapping

from belay.sqlite.errors import SqlError
from conformance.case_format import Json, case_profile
from conformance.execution_profile import ExecutionProfile, profile_from_wire
from conformance.native_connection import SOURCE_ID
from conformance.native_library import DEFAULT_ENGINE_VERSION
from conformance.native_limits import DOCUMENTED_LIMITS
from conformance.record_versions import PROFILED


def unsupported_setting(profile: ExecutionProfile) -> str | None:
    """The first execution setting of the profile that the model does not implement, or `None`."""
    settings = (("foreign keys", profile.foreign_keys), ("recursive triggers", profile.recursive_triggers),
                ("IMMEDIATE transactions", profile.transaction_mode != "deferred"),
                ("read-only access", profile.access_mode != "read-write"),
                ("untrusted schema mode", not profile.trusted_schema),
                ("other writers", bool(profile.other_writers)))
    return next((name for name, used in settings if used), None)


def modeled_profile(record: Mapping[str, Json]) -> Json:
    """The case profile (`case_format.case_profile`) of a record or subject input.

    Raises `SqlError` with status `UNSUPPORTED` when the record's profile uses a setting
    that the model does not implement.
    """
    if record.get("nativeVersion") not in PROFILED:
        return case_profile(DEFAULT_ENGINE_VERSION, SOURCE_ID, DOCUMENTED_LIMITS)
    profile = profile_from_wire(record["profile"])
    setting = unsupported_setting(profile)
    if setting is not None:
        raise SqlError("UNSUPPORTED", f"{record.get('name', 'case')}: the model does not implement {setting}, which "
                       f"the execution profile {profile.name} uses; this case stays out of scope until it does")
    return case_profile(profile.engine_version, profile.source_id, profile.effective_limits(),
                        dqs_dml=profile.dqs_dml, dqs_ddl=profile.dqs_ddl)
