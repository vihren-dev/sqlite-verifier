"""Replay every authored and synthetic case plus a bounded, identity-selected upstream tier."""

import argparse
from collections import Counter, defaultdict
import hashlib
import json
import os
from pathlib import Path
from time import monotonic

from conformance.case_format import Json
from conformance.corpus import load, replay
from conformance.native_workers import replay_native_cases
from conformance.native_storage import serialized
from conformance.workload import bound_records

AUTHORED_PARTS = {"boundary-interaction", "requirement", "issue-boundary"}
AUTHORED_COUNTS_BY_VERSION = {4: 66, 5: 69}
POLICY: dict[str, Json] = {"version": 1, "mandatory": "all-authored-and-synthetic",
    "upstreamIdentity": "sha256-canonical-json-[source,name]",
    "minimumPerNonemptySourceShard": 1, "additionalUpstream": 8}
VERDICTS = {"AGREE", "DISAGREE", "MODEL_UNSUPPORTED", "HARNESS_ERROR"}
PHASE_LIMIT_SECONDS = 120


def digest(value: Json) -> str:
    """Bind structured identities without depending on formatting or mapping insertion order."""
    return hashlib.sha256(serialized(value)).hexdigest()


def identity(record: dict[str, Json]) -> dict[str, Json]:
    """Give generic cases their immutable source and part alongside the unique corpus name."""
    return {"name": record["name"], "part": record["part"],
            "upstreamSource": record["upstream"]["file"] if record["part"] == "upstream" else None}


def select(records: list[dict[str, Json]]) -> list[dict[str, Json]]:
    """Sample by source/name only; native refusals and current-model verdicts never select cases."""
    authored: list[dict[str, Json]] = []
    groups: dict[str, list[dict[str, Json]]] = defaultdict(list)
    names: set[str] = set()
    for record in records:
        if not isinstance(record.get("name"), str) or not record["name"] or record["name"] in names:
            raise ValueError("Invalid or duplicate tier case name")
        names.add(record["name"])
        if record.get("part") in AUTHORED_PARTS:
            authored.append(record)
        elif record.get("part") == "upstream":
            upstream = record.get("upstream")
            if not isinstance(upstream, dict) or not isinstance(upstream.get("file"), str) or not upstream["file"]:
                raise ValueError("Missing upstream tier source")
            groups[upstream["file"]].append(record)
        else:
            raise ValueError("Unknown generic tier part")

    def rank(record: dict[str, Json]) -> tuple[str, str, str]:
        """Names break a hypothetical hash collision without consulting case outcomes."""
        source, name = record["upstream"]["file"], record["name"]
        return digest([source, name]), source, name

    ordered = [sorted(group, key=rank) for group in groups.values()]
    upstream = [group[0] for group in ordered]
    upstream.extend(sorted([record for group in ordered for record in group[1:]], key=rank)[:8])
    return sorted(authored, key=lambda record: (record["part"], record["name"])) + sorted(upstream, key=rank)


def binding(directory: Path, manifest: dict[str, Json], selected: list[dict[str, Json]],
            result: dict[str, Json]) -> dict[str, Json]:
    """Bind the complete denominator, profiles and transport/evidence manifest to selected results."""
    identities = [identity(record) for record in selected]
    return {"corpusVersion": manifest["corpusVersion"], "casesSha256": manifest["casesSha256"],
        "manifestSha256": hashlib.sha256((directory / "manifest.json").read_bytes()).hexdigest(),
        "executionProfiles": manifest["executionProfiles"], "denominator": manifest["recordedCases"],
        "selectedDenominator": len(selected), "selectedNames": [record["name"] for record in selected],
        "selectedIdentities": identities, "selectedIdentitiesSha256": digest(identities),
        "nativeReplayPassed": True, **result}


def checked_replay(records: list[dict[str, Json]], runtime: Path) -> dict[str, Json]:
    """Require an exact verdict denominator and fail on any disagreement or harness failure."""
    result = replay(records, runtime)
    cases = result.get("cases")
    if (not isinstance(cases, list) or len(cases) != len(records)
            or any(not isinstance(case, dict) or case.get("name") != record["name"]
                   or case.get("verdict") not in VERDICTS for record, case in zip(records, cases))):
        raise ValueError("Tier replay case identities or verdicts differ")
    counts = dict(Counter(case["verdict"] for case in cases))
    if result.get("counts") != counts:
        raise ValueError("Tier replay verdict denominator differs")
    failed = [case["name"] for case in cases if case["verdict"] in {"DISAGREE", "HARNESS_ERROR"}]
    if failed:
        raise ValueError(f"Tier replay failed: {failed}")
    return result


def runtime_binding(runtime: Path) -> dict[str, Json]:
    """Require and identify both executable oracles even when every case is unsupported."""
    result: dict[str, Json] = {}
    for role, relative in (("parser", "build/sqlite-parser"), ("compiledModel", ".lake/build/bin/conformance-runner")):
        path = runtime / relative
        if not path.is_file() or not os.access(path, os.X_OK):
            raise ValueError(f"Tier runtime executable is missing or not executable: {relative}")
        result[role] = {"path": relative, "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}
    return result


def report(generic: Path, synthetic: Path, runtime: Path, *, temporary_root: Path | None = None,
           fixture_paths: list[Path] | None = None) -> dict[str, Json]:
    """Time fresh loading, exact-profile native replay and current-model classification together.

    Optional storage and path auditing retain actual ordinary fixtures from the
    independent development workers, including paths from failed comparisons.
    """
    started = monotonic()
    runtime_identity = runtime_binding(runtime)
    generic_manifest, records = load(generic)
    synthetic_corpus = synthetic / "corpus"
    synthetic_manifest, synthetic_records = bound_records(synthetic, synthetic_corpus)
    authored_count = AUTHORED_COUNTS_BY_VERSION.get(generic_manifest["corpusVersion"])
    if (authored_count is None or synthetic_manifest["corpusVersion"] != 4
            or any(record["nativeVersion"] != 4 for record in records + synthetic_records)
            or sum(record["part"] in AUTHORED_PARTS for record in records) != authored_count
            or len(synthetic_records) != 2):
        raise ValueError("Tier requires v4/v5 authored membership and two synthetic v4 cases")
    selected = select(records)
    replay_native_cases(selected + synthetic_records, temporary_root=temporary_root, fixture_paths=fixture_paths)
    generic_result = checked_replay(selected, runtime)
    synthetic_result = checked_replay(synthetic_records, runtime)
    result: dict[str, Json] = {"reportVersion": 1, "tier": "development-sample", "runtime": runtime_identity,
        "policy": dict(POLICY),
        "policySha256": digest(POLICY), "generic": binding(generic, generic_manifest, selected, generic_result),
        "synthetic": binding(synthetic_corpus, synthetic_manifest, synthetic_records, synthetic_result),
        "denominator": len(records) + len(synthetic_records),
        "selectedDenominator": len(selected) + len(synthetic_records),
        "counts": dict(Counter(generic_result["counts"]) + Counter(synthetic_result["counts"]))}
    elapsed = monotonic() - started
    if elapsed >= PHASE_LIMIT_SECONDS:
        raise ValueError(f"Fresh conformance replay phase exceeded {PHASE_LIMIT_SECONDS} seconds: {elapsed:.3f}")
    result["measurement"] = {"phase": "fresh-load-native-replay-model-classification",
                             "seconds": elapsed, "limitSeconds": PHASE_LIMIT_SECONDS}
    return result


def main() -> None:
    """Run the frozen development tier with a process timeout supplied by its test target."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--corpus", type=Path, default=Path("conformance/corpus-v5"))
    parser.add_argument("--synthetic", type=Path, default=Path("conformance/synthetic-workload"))
    parser.add_argument("--runtime-root", type=Path, default=Path("build/conformance"))
    parser.add_argument("--temporary-root", type=Path, help="Directory for ordinary native case files")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    result = report(args.corpus, args.synthetic, args.runtime_root.resolve(), temporary_root=args.temporary_root)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps({key: result[key] for key in ("selectedDenominator", "counts", "measurement")}))


if __name__ == "__main__":
    main()
