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
from conformance.upstream_selection import candidate_reasons
from conformance.upstream_assertions import assertions
from conformance.upstream_helpers import readonly_spans, join_commands


def evidence(source: str, line: int) -> list[dict[str, Json]]:
    """Retain the nearest EVIDENCE-OF comment block; ambiguous blocks get no automatic credit."""
    lines = source.splitlines()[:max(0, line - 1)]
    references: list[dict[str, Json]] = []
    for index in reversed(range(len(lines))):
        text = lines[index].strip()
        if references and text and not text.startswith("#"):
            break
        found = re.search(r"EVIDENCE-OF: (R-\d{5}-\d{5})", text)
        if found:
            references.insert(0, {"id": found[1], "line": index + 1})
    return references


def pilot(fixture: Path, upstream: Path, output: Path, limit: int, patterns: tuple[str, ...] = ("alter*.test",)) -> dict[str, Json]:
    """Bound pilot size explicitly; all runtime candidates retain a selection/exclusion reason."""
    output.mkdir(parents=True, exist_ok=True)
    identity = subprocess.run([str(fixture)], input="sqlite3 db :memory:\nputs [db eval {SELECT sqlite_source_id()}]\nexit\n",
        text=True, capture_output=True, timeout=10)
    if identity.returncode or SOURCE_ID not in identity.stdout:
        raise ValueError("Upstream testfixture source ID differs from the pinned engine")
    report: list[Json] = []
    corpus: list[Json] = []
    proxy = Path(__file__).with_name("upstream_proxy.tcl").resolve()
    for file in sorted({file for pattern in patterns for file in (upstream / "test").glob(pattern)}):
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
                exclusions = candidate_reasons(candidate, selected=selected, limit=limit)
                reason = "; ".join(exclusions)
                if not reason:
                    try:
                        record = record_sql(candidate["prefix"], join_commands(candidate["commands"]),
                            name=f"{file.stem}:{candidate['id']}:{occurrence}", setup_helpers=candidate["prefixHelpers"],
                            migration_readonly_spans=readonly_spans(candidate["commands"], candidate["helpers"]),
                            auxiliary_replay=any(helper.startswith("aux:") for helper in candidate["helpers"]))
                        check_results(record, candidate)
                        record = minimize_prefix(record)
                        repeated = record_sql(record["setupCommands"], record["migrationSql"], name=record["name"])
                        if (record["initial"], record["trace"]) != (repeated["initial"], repeated["trace"]):
                            raise ValueError("native evidence is not repeatable")
                        record["upstream"] = {"file": file.name, "id": candidate["id"],
                            "occurrence": occurrence, "expectedTcl": candidate["expectedTcl"], "sourceSha256": base["sha256"],
                            "fileRequirementReferences": sorted(set(re.findall(r"R-\d{5}-\d{5}", file.read_text())))}
                        references = evidence(file.read_text(), candidate["line"])
                        record["upstream"]["evidenceContext"] = references
                        record["upstream"]["sourceLine"] = candidate["line"]
                        record["requirements"] = [item["id"] for item in references] if len(references) == 1 else []
                        corpus.append(record)
                        selected += 1
                    except (ValueError, RuntimeError) as error:
                        reason = f"native acquisition: {error}"
                        exclusions.append(reason)
                reasons[reason or "recorded"] += 1
                instances.append({"id": candidate["id"], "occurrence": occurrence,
                                  "result": reason or "recorded", "exclusions": exclusions})
            report.append({**base, "runtimeExit": result.returncode, "runtimeAssertions": len(candidates),
                "recorded": selected, "reasons": dict(reasons), "instances": instances,
                "runtimeDiagnostics": (result.stdout + result.stderr)[-1500:] if result.returncode else ""})
    payload = "".join(json.dumps(case, separators=(",", ":")) + "\n" for case in corpus).encode()
    (output / "cases.jsonl.gz").write_bytes(gzip.compress(payload, mtime=0))
    result: dict[str, Json] = {"corpusVersion": 1, "sourceRelease": "3.51.0", "perFileLimit": limit, "patterns": list(patterns),
        "sourceId": SOURCE_ID, "sourceArchiveSha256": "5330719b8b80bf563991ff7a373052943f5357aae76cd1f3367eab845d3a75b7",
        "extractorSha256": {name: hashlib.sha256(Path(__file__).with_name(name).read_bytes()).hexdigest()
                            for name in ("upstream_pilot.py", "upstream_assertions.py", "upstream_helpers.py", "upstream_proxy.tcl", "upstream_fidelity.py", "upstream_selection.py", "native_record.py")},
        "files": report, "recordedCases": len(corpus), "casesSha256": hashlib.sha256(payload).hexdigest()}
    (output / "manifest.json").write_text(json.dumps(result, indent=2) + "\n")
    return result


def main() -> None:
    """Run an explicitly bounded upstream pilot without modifying upstream sources."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--fixture", type=Path, required=True)
    parser.add_argument("--upstream", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--pattern", action="append", default=[])
    parser.add_argument("--per-file", type=int, default=20)
    args = parser.parse_args()
    result = pilot(args.fixture.resolve(), args.upstream.resolve(), args.output, args.per_file, tuple(args.pattern or ["alter*.test"]))
    print(json.dumps({"files": len(result["files"]), "cases": result["recordedCases"]}))


if __name__ == "__main__":
    main()
