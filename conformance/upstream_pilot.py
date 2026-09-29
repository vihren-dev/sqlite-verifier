"""Execute pinned upstream Tcl assertions and freeze fresh single-main-database native cases."""

import argparse
from collections import Counter
import gzip
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
from tempfile import TemporaryDirectory

from conformance.case_format import Json
from conformance.native_record import record_sql
from conformance.native_connection import SOURCE_ID
from conformance.upstream_fidelity import check_results, minimize_prefix


def assertions(events: str) -> list[dict[str, Json]]:
    """Consume runtime events, retaining expanded test instances and reset-scoped prefixes."""
    prefix: list[str] = []
    codes: list[int] = []
    expected: list[list[str]] = []
    excluded: set[str] = set()
    rows: list[dict[str, Json]] = []
    active: dict[str, Json] | None = None
    for line in events.splitlines():
        fields = [bytes.fromhex(field).decode() for field in line.split("\t")]
        kind, *args = fields
        if kind == "reset":
            prefix, codes, excluded, expected = [], [], set(), []
            if active is not None:
                active.update(prefix=[], prefixCodes=[], prefixResults=[], commands=[], codes=[], results=[])
        elif kind == "open" and args[0] != "db":
            excluded.add("multiple connections")
        elif kind == "exclude":
            excluded.add(args[0])
        elif kind == "begin":
            active = {"id": args[0], "expectedTcl": args[1], "prefix": list(prefix),
                      "prefixCodes": list(codes), "prefixResults": list(expected), "commands": [], "codes": [], "results": [], "failed": False}
        elif kind == "sql":
            if args[0] != "db" or args[2] != "0" or args[3] != "eval":
                excluded.add("connection or SQL callback context")
            prefix.append(args[1])
            if active is not None:
                active["commands"].append(args[1])
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


def pilot(fixture: Path, upstream: Path, output: Path, limit: int) -> dict[str, Json]:
    """Bound pilot size explicitly; all runtime candidates retain a selection/exclusion reason."""
    output.mkdir(parents=True, exist_ok=True)
    identity = subprocess.run([str(fixture)], input="sqlite3 db :memory:\nputs [db eval {SELECT sqlite_source_id()}]\nexit\n",
        text=True, capture_output=True, timeout=10)
    if identity.returncode or SOURCE_ID not in identity.stdout:
        raise ValueError("Upstream testfixture source ID differs from the pinned engine")
    report: list[Json] = []
    corpus: list[Json] = []
    proxy = Path(__file__).with_name("upstream_proxy.tcl").resolve()
    for file in sorted((upstream / "test").glob("alter*.test")):
        base: dict[str, Json] = {"file": file.name, "sha256": hashlib.sha256(file.read_bytes()).hexdigest()}
        if any(part in file.stem for part in ("fault", "malloc", "corrupt", "auth", "qf")):
            report.append({**base, "excludedFile": "fault injection, authorizer, corruption or query-plan context"})
            continue
        with TemporaryDirectory(prefix="upstream-pilot-") as directory:
            events = Path(directory) / "events.tsv"
            try:
                result = subprocess.run([str(fixture), str(proxy)], cwd=directory,
                    env={**os.environ, "CONFORMANCE_EVENTS": str(events), "CONFORMANCE_TEST": str(file)},
                    capture_output=True, text=True, timeout=60)
            except subprocess.TimeoutExpired:
                report.append({**base, "excludedFile": "upstream runtime exceeded 60 seconds"})
                continue
            candidates = assertions(events.read_text()) if events.exists() else []
            reasons: Counter[str] = Counter()
            selected = 0
            instances: list[Json] = []
            for occurrence, candidate in enumerate(candidates):
                reason = "; ".join(candidate["exclusions"])
                if candidate["failed"]:
                    reason = "upstream Tcl expectation failed"
                elif not candidate["commands"]:
                    reason = "no SQL observation"
                elif any(candidate["codes"][:-1]):
                    reason = "assertion continues after a SQL error"
                elif selected >= limit:
                    reason = "bounded pilot selection limit"
                if not reason:
                    try:
                        record = record_sql(candidate["prefix"], "\n".join(candidate["commands"]),
                            name=f"{file.stem}:{candidate['id']}:{occurrence}")
                        check_results(record, candidate)
                        record = minimize_prefix(record)
                        record["upstream"] = {"file": file.name, "id": candidate["id"],
                            "occurrence": occurrence, "expectedTcl": candidate["expectedTcl"], "sourceSha256": base["sha256"],
                            "fileRequirementReferences": sorted(set(re.findall(r"R-\d{5}-\d{5}", file.read_text())))}
                        corpus.append(record)
                        selected += 1
                    except (ValueError, RuntimeError) as error:
                        reason = f"native acquisition: {error}"
                reasons[reason or "recorded"] += 1
                instances.append({"id": candidate["id"], "occurrence": occurrence, "result": reason or "recorded"})
            report.append({**base, "runtimeExit": result.returncode, "runtimeAssertions": len(candidates),
                "recorded": selected, "reasons": dict(reasons), "instances": instances,
                "runtimeDiagnostics": (result.stdout + result.stderr)[-1500:] if result.returncode else ""})
    payload = "".join(json.dumps(case, separators=(",", ":")) + "\n" for case in corpus).encode()
    (output / "cases.jsonl.gz").write_bytes(gzip.compress(payload, mtime=0))
    result: dict[str, Json] = {"corpusVersion": 1, "sourceRelease": "3.51.0", "perFileLimit": limit,
        "sourceId": SOURCE_ID, "sourceArchiveSha256": "5330719b8b80bf563991ff7a373052943f5357aae76cd1f3367eab845d3a75b7",
        "extractorSha256": {name: hashlib.sha256(Path(__file__).with_name(name).read_bytes()).hexdigest()
                            for name in ("upstream_pilot.py", "upstream_proxy.tcl", "upstream_fidelity.py", "native_record.py")},
        "files": report, "recordedCases": len(corpus), "casesSha256": hashlib.sha256(payload).hexdigest()}
    (output / "manifest.json").write_text(json.dumps(result, indent=2) + "\n")
    return result


def main() -> None:
    """Run an explicitly bounded upstream pilot without modifying upstream sources."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--fixture", type=Path, required=True)
    parser.add_argument("--upstream", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--per-file", type=int, default=20)
    args = parser.parse_args()
    result = pilot(args.fixture.resolve(), args.upstream.resolve(), args.output, args.per_file)
    print(json.dumps({"files": len(result["files"]), "cases": result["recordedCases"]}))


if __name__ == "__main__":
    main()
