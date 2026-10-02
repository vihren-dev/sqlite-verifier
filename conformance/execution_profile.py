"""Measured native execution conditions, separate from model admission."""

from dataclasses import dataclass

from conformance.case_format import Json
from conformance.native_connection import Connection
from conformance.native_metadata import text

IGNORED_SETTINGS = {"journal_mode", "synchronous", "cache_size", "temp_store", "mmap_size", "busy_timeout"}

@dataclass(frozen=True)
class ExecutionProfile:
    """Immutable identity and conditions established before any case SQL executes."""

    name: str
    version: int
    engine_version: str
    source_id: str
    compile_options: tuple[str, ...]
    foreign_keys: bool = False
    recursive_triggers: bool = False
    transaction_mode: str = "deferred"
    clock: str = "excluded"
    ignored_settings: tuple[tuple[str, str], ...] = ()
    other_writers: tuple[str, ...] = ()
    timezone: str = "UTC"
    format_version: int = 1
    trusted_schema: bool = True
    dqs_dml: bool = True
    dqs_ddl: bool = True
    access_mode: str = "read-write"

    def __post_init__(self) -> None:
        """Refuse malformed or unimplemented conditions rather than approximate them."""
        if (not self.name or type(self.version) is not int or self.version < 1
                or not self.engine_version or not self.source_id
                or not self.compile_options
                or tuple(sorted(set(self.compile_options))) != self.compile_options
                or type(self.foreign_keys) is not bool or type(self.recursive_triggers) is not bool
                or type(self.format_version) is not int or self.format_version not in (1, 2)
                or any(type(value) is not bool for value in (self.trusted_schema, self.dqs_dml, self.dqs_ddl))
                or self.access_mode not in {"read-write", "read-only"}
                or self.format_version == 1 and (not self.trusted_schema or not self.dqs_dml
                    or not self.dqs_ddl or self.access_mode != "read-write")
                or self.transaction_mode not in {"deferred", "immediate"}
                or self.clock not in {"excluded", "unix-milliseconds-v1"}
                or self.timezone != "UTC"
                or any(setting not in IGNORED_SETTINGS or not reason for setting, reason in self.ignored_settings)):
            raise ValueError("Invalid or unsupported execution profile")

    def establish(self, connection: Connection) -> None:
        """Check exact engine identity, set behavioral settings, then read them back."""
        engine = connection.library
        options = tuple(sorted(text(row[0]) for row in connection.query("PRAGMA compile_options;")))
        if (engine.sqlite3_libversion().decode() != self.engine_version
                or engine.sqlite3_sourceid().decode() != self.source_id
                or options != self.compile_options):
            raise ValueError("Execution profile engine identity differs")
        if connection.transaction_open:
            raise ValueError("Execution profile must be established outside a transaction")
        for setting, enabled in (("foreign_keys", self.foreign_keys),
                                 ("recursive_triggers", self.recursive_triggers),
                                 ("trusted_schema", self.trusted_schema)):
            connection.execute_script(f"PRAGMA {setting}={int(enabled)};")
        for option, enabled in ((1013, self.dqs_dml), (1014, self.dqs_ddl)):
            if connection.configure(option, int(enabled)) != int(enabled):
                raise ValueError("Execution profile DQS setting readback differs")
        self.verify_settings(connection)
        connection.readonly_evidence = self.access_mode == "read-only"

    def permits_setting(self, setting: str, value: bytes | None) -> bool:
        """Allow a query or an explicit boolean value already required by this profile."""
        expected = {"foreign_keys": self.foreign_keys, "recursive_triggers": self.recursive_triggers,
                    "trusted_schema": self.trusted_schema, "writable_schema": False}
        booleans = {b"0": False, b"off": False, b"false": False, b"no": False,
                    b"1": True, b"on": True, b"true": True, b"yes": True}
        return setting in expected and (value is None or booleans.get(value.lower()) == expected[setting])

    def verify_settings(self, connection: Connection) -> None:
        """Read back behavioral conditions after SQL, without resetting a changed connection."""
        for setting, enabled in (("foreign_keys", self.foreign_keys), ("recursive_triggers", self.recursive_triggers),
                                 ("trusted_schema", self.trusted_schema), ("writable_schema", False)):
            if connection.query(f"PRAGMA {setting};") != [((1, int(enabled)),)]:
                raise ValueError(f"Execution profile setting readback differs: {setting}")
        for option, enabled in ((1013, self.dqs_dml), (1014, self.dqs_ddl)):
            if connection.configure(option, -1) != int(enabled):
                raise ValueError("Execution profile DQS setting readback differs")
        readonly = connection.library.sqlite3_db_readonly(connection.handle, b"main")
        if connection.access_mode != self.access_mode or readonly != int(self.access_mode == "read-only"):
            raise ValueError("Execution profile access mode readback differs")

    def to_wire(self) -> dict[str, Json]:
        """Keep profile identity in a stable JSON record alongside native evidence."""
        value: dict[str, Json] = {"name": self.name, "version": self.version,
            "engineVersion": self.engine_version, "sourceId": self.source_id,
            "compileOptions": list(self.compile_options), "foreignKeys": self.foreign_keys,
            "recursiveTriggers": self.recursive_triggers, "transactionMode": self.transaction_mode,
            "clock": self.clock, "ignoredSettings": [list(item) for item in self.ignored_settings],
            "otherWriters": list(self.other_writers), "timezone": self.timezone}
        if self.format_version == 2:
            value.update({"formatVersion": 2, "trustedSchema": self.trusted_schema,
                          "dqsDml": self.dqs_dml, "dqsDdl": self.dqs_ddl, "accessMode": self.access_mode})
        return value


def profile_from_wire(value: Json) -> ExecutionProfile:
    """Validate external profile transport before constructing native conditions."""
    fields = {"name", "version", "engineVersion", "sourceId", "compileOptions", "foreignKeys",
              "recursiveTriggers", "transactionMode", "clock", "ignoredSettings", "otherWriters", "timezone"}
    extended = isinstance(value, dict) and "formatVersion" in value
    if extended:
        fields |= {"formatVersion", "trustedSchema", "dqsDml", "dqsDdl", "accessMode"}
    if not isinstance(value, dict) or set(value) != fields:
        raise ValueError("Invalid execution profile fields")
    if extended and (type(value["formatVersion"]) is not int or value["formatVersion"] != 2
            or any(type(value[key]) is not bool for key in ("trustedSchema", "dqsDml", "dqsDdl"))
            or not isinstance(value["accessMode"], str)):
        raise ValueError("Invalid execution profile format or conditions")
    strings = ("name", "engineVersion", "sourceId", "transactionMode", "clock", "timezone")
    if (any(not isinstance(value[key], str) for key in strings)
            or type(value["version"]) is not int
            or any(type(value[key]) is not bool for key in ("foreignKeys", "recursiveTriggers"))
            or any(not isinstance(value[key], list) or any(not isinstance(item, str) for item in value[key])
                   for key in ("compileOptions", "otherWriters"))
            or not isinstance(value["ignoredSettings"], list)
            or any(not isinstance(item, list) or len(item) != 2
                   or any(not isinstance(part, str) for part in item) for item in value["ignoredSettings"])):
        raise ValueError("Invalid execution profile values")
    return ExecutionProfile(value["name"], value["version"], value["engineVersion"], value["sourceId"],
        tuple(value["compileOptions"]), value["foreignKeys"], value["recursiveTriggers"],
        value["transactionMode"], value["clock"],
        tuple((item[0], item[1]) for item in value["ignoredSettings"]), tuple(value["otherWriters"]), value["timezone"],
        2 if extended else 1, value.get("trustedSchema", True), value.get("dqsDml", True),
        value.get("dqsDdl", True), value.get("accessMode", "read-write"))


def measured_profile(connection: Connection, *, name: str, version: int = 1,
                     foreign_keys: bool = False, recursive_triggers: bool = False,
                     transaction_mode: str = "deferred", clock: str = "excluded",
                     format_version: int = 1, trusted_schema: bool = True,
                     dqs_dml: bool = True, dqs_ddl: bool = True,
                     access_mode: str = "read-write") -> ExecutionProfile:
    """Capture running-engine identity; workload-driver measurements remain external."""
    engine = connection.library
    return ExecutionProfile(name, version, engine.sqlite3_libversion().decode(),
        engine.sqlite3_sourceid().decode(),
        tuple(sorted(text(row[0]) for row in connection.query("PRAGMA compile_options;"))),
        foreign_keys, recursive_triggers, transaction_mode, clock, format_version=format_version,
        trusted_schema=trusted_schema, dqs_dml=dqs_dml, dqs_ddl=dqs_ddl, access_mode=access_mode)


def recorded_profile(record: dict[str, Json]) -> ExecutionProfile:
    """Validate profile and clock evidence before replay or unsupported admission."""
    profile = profile_from_wire(record["profile"])
    if profile.source_id != record["sourceId"]:
        raise ValueError("Execution profile source identity differs from record")
    clocks = [record.get("setupClockUnixMilliseconds")]
    if profile.clock == "unix-milliseconds-v1":
        clocks.extend(event.get("clockUnixMilliseconds") for event in record["trace"])
        if any(type(value) is not int or not -210866760000000 <= value < 253402300800000 for value in clocks):
            raise ValueError("Invalid recorded execution profile clock")
    elif clocks != [None] or any("clockUnixMilliseconds" in event for event in record["trace"]):
        raise ValueError("Excluded clock profile carries clock inputs")
    return profile


def validate_manifest_profiles(manifest: dict[str, Json], records: list[dict[str, Json]]) -> None:
    """Bind every explicit-profile case to one unambiguous manifest declaration."""
    declarations = manifest.get("executionProfiles", [])
    if not isinstance(declarations, list):
        raise ValueError("Invalid manifest execution profiles")
    profiles = [profile_from_wire(value) for value in declarations]
    identities = [(profile.name, profile.version) for profile in profiles]
    if len(set(identities)) != len(identities):
        raise ValueError("Duplicate manifest execution profile identity")
    for record in records:
        if record.get("nativeVersion") == 4 and recorded_profile(record) not in profiles:
            raise ValueError("Native record execution profile differs from manifest")
