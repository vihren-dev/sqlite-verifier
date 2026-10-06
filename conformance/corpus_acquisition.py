"""Verify v5 accepted membership against its retained, versioned acquisition conditions."""

from collections import Counter
from fnmatch import fnmatchcase
import re

from conformance.case_format import Json
from conformance.corpus_shards import natural
from conformance.execution_profile import ExecutionProfile, profile_from_wire
from conformance.freeze_profiles import file_conditions, record_conditions, result_precision, result_nullvalue
from conformance.upstream_profiles import RETAINED_TCL_PRECISION_POLICY_VERSIONS


def strings(value: Json) -> list[str]:
    """Require distinct nonempty labels or patterns rather than coercing malformed evidence."""
    if (not isinstance(value, list) or any(not isinstance(item, str) or not item for item in value)
            or len(set(value)) != len(value)):
        raise ValueError("Invalid retained acquisition strings")
    return value


def retained_profiles(report: dict[str, Json]) -> tuple[dict[str, Json], dict[tuple[bool, str], ExecutionProfile]]:
    """Interpret policy v1 using retained routes; today's source catalog is irrelevant to loading."""
    policy = report.get("sourceExecutionProfilePolicy")
    if (not isinstance(policy, dict) or set(policy) != {"version", "foreignKeyOnPatterns",
            "controlledClockPatterns", "clockUnixMilliseconds", "transactionMode", "profiles"}
            or type(policy["version"]) is not int or policy["version"] != 1
            or policy["transactionMode"] != "deferred"
            or type(policy["clockUnixMilliseconds"]) is not int
            or policy["clockUnixMilliseconds"] % 1000
            or not 0 < policy["clockUnixMilliseconds"] // 1000 <= 2147483647):
        raise ValueError("Invalid retained source profile policy")
    strings(policy["foreignKeyOnPatterns"])
    strings(policy["controlledClockPatterns"])
    precision = report.get("tclDisplayPrecisionPolicy")
    if (not isinstance(precision, dict) or set(precision) != {"version", "requested", "establishAfter"}
            or type(precision["version"]) is not int
            or precision["version"] not in RETAINED_TCL_PRECISION_POLICY_VERSIONS
            or type(precision["requested"]) is not int or precision["requested"] != 0
            or precision["establishAfter"] != "tester.tcl"):
        raise ValueError("Invalid retained Tcl precision policy")
    routes, declarations = policy["profiles"], report.get("executionProfiles")
    if not isinstance(routes, list) or len(routes) != 4 or not isinstance(declarations, list):
        raise ValueError("Invalid retained profile routes")
    profiles = [profile_from_wire(value) for value in declarations]
    by_name = {profile.name: profile for profile in profiles}
    if len(profiles) != 4 or len(by_name) != 4:
        raise ValueError("Invalid retained profile declarations")
    result: dict[tuple[bool, str], ExecutionProfile] = {}
    used: set[str] = set()
    for route in routes:
        if (not isinstance(route, dict) or set(route) != {"name", "version", "foreignKeys", "clock"}
                or not isinstance(route["name"], str) or route["name"] in used
                or type(route["version"]) is not int or route["version"] < 1
                or type(route["foreignKeys"]) is not bool or not isinstance(route["clock"], str)
                or route["clock"] not in {"excluded", "unix-milliseconds-v1"}):
            raise ValueError("Invalid retained profile route")
        profile = by_name.get(route["name"])
        key = (route["foreignKeys"], route["clock"])
        if (profile is None or key in result or profile.version != route["version"]
                or profile.foreign_keys != key[0] or profile.clock != key[1]
                or profile.engine_version != report.get("sourceRelease") or profile.source_id != report.get("sourceId")
                or profile.compile_options != profiles[0].compile_options or profile.format_version != 1
                or profile.transaction_mode != policy["transactionMode"] or profile.recursive_triggers
                or profile.ignored_settings or profile.other_writers):
            raise ValueError("Retained profile conditions differ")
        result[key] = profile
        used.add(profile.name)
    return policy, result


def verify(report: dict[str, Json], records: list[dict[str, Json]]) -> None:
    """Bind every upstream case to one accepted source instance and its actual capture conditions."""
    if type(report.get("corpusVersion")) is not int or report["corpusVersion"] != 1:
        raise ValueError("Unsupported retained acquisition version")
    policy, profiles = retained_profiles(report)
    catalog, files = report.get("sourceCatalog"), report.get("files")
    if (not isinstance(catalog, list) or not isinstance(files, list) or len(catalog) != len(files)
            or any(not isinstance(item, dict) for item in catalog + files)
            or [item.get("file") for item in catalog] != [item.get("file") for item in files]):
        raise ValueError("Retained source catalog differs")
    names = strings([file.get("file") for file in files])
    accepted: dict[tuple[str, str, int], tuple[dict[str, Json], ExecutionProfile, int | None, Json, Json]] = {}
    for filename, file, declaration in zip(names, files, catalog, strict=True):
        labels, exclusions = strings(declaration.get("features")), strings(declaration.get("fileExclusions"))
        if (file.get("features") != labels or file.get("fileExclusions") != exclusions
                or not isinstance(file.get("sha256"), str) or not re.fullmatch(r"[0-9a-f]{64}", file["sha256"])
                or file.get("timedOut") or file.get("incomplete")):
            raise ValueError("Retained source evidence differs")
        if exclusions:
            if (file.get("excludedFile") != "; ".join(exclusions)
                    or {"instances", "runtimeAssertions", "runtimeExit", "runtimeComplete", "recorded"} & file.keys()):
                raise ValueError("Retained source exclusion differs")
            continue
        foreign_keys = any(fnmatchcase(filename, pattern) for pattern in policy["foreignKeyOnPatterns"])
        controlled = any(fnmatchcase(filename, pattern) for pattern in policy["controlledClockPatterns"])
        profile = profiles[foreign_keys, "unix-milliseconds-v1" if controlled else "excluded"]
        clock = policy["clockUnixMilliseconds"] if controlled else None
        file_conditions(file, profile, clock)
        instances = file.get("instances")
        if ("excludedFile" in file or type(file.get("runtimeExit")) is not int
                or file.get("runtimeComplete") is not True or not isinstance(instances, list)
                or natural(file.get("runtimeAssertions")) != len(instances)):
            raise ValueError("Retained runtime completion differs")
        count = 0
        for occurrence, instance in enumerate(instances):
            if (not isinstance(instance, dict) or not isinstance(instance.get("id"), str) or not instance["id"]
                    or natural(instance.get("occurrence")) != occurrence):
                raise ValueError("Invalid retained acquisition instance")
            reasons = strings(instance.get("exclusions"))
            if instance.get("result") != ("; ".join(reasons) or "recorded"):
                raise ValueError("Retained acquisition result differs")
            result_precision(instance.get("tclResultPrecision"), accepted=not reasons,
                             policy_version=report["tclDisplayPrecisionPolicy"]["version"])
            result_nullvalue(instance.get("tclNullvalueEvidence"), instance["tclResultPrecision"], accepted=not reasons)
            if not reasons:
                accepted[filename, instance["id"], occurrence] = (file, profile, clock,
                    instance["tclResultPrecision"], instance["tclNullvalueEvidence"])
                count += 1
        reasons = file.get("reasons")
        if (natural(file.get("recorded")) != count or not isinstance(reasons, dict)
                or any(type(value) is not int or value < 1 for value in reasons.values())
                or reasons != dict(Counter(instance["result"] for instance in instances))):
            raise ValueError("Retained candidate accounting differs")
    if natural(report.get("recordedCases")) != len(records):
        raise ValueError("Retained accepted count differs")
    observed: set[tuple[str, str, int]] = set()
    for record in records:
        provenance = record.get("upstream")
        if (not isinstance(provenance, dict) or any(not isinstance(provenance.get(key), str)
                or not provenance[key] for key in ("file", "id"))):
            raise ValueError("Missing retained upstream provenance")
        identity = (provenance["file"], provenance["id"], natural(provenance.get("occurrence")))
        evidence = accepted.get(identity)
        if evidence is None or identity in observed:
            raise ValueError("Retained accepted membership differs")
        file, profile, clock, precision, nullvalue = evidence
        if (type(record.get("nativeVersion")) is not int or record["nativeVersion"] != 4
                or record.get("part") != "upstream" or record.get("features") != file["features"]
                or record.get("featureMetadataScope") != "source-file"
                or provenance.get("sourceSha256") != file["sha256"]):
            raise ValueError("Retained case source evidence differs")
        record_conditions(record, profile, precision, clock, nullvalue)
        observed.add(identity)
    if observed != set(accepted):
        raise ValueError("Retained accepted membership differs")
