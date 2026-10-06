"""Retain every alternating cold pair and extend the same nine to 25 only when the policy requires it."""

from collections.abc import Mapping
from dataclasses import asdict, replace
import json
from pathlib import Path
from tempfile import NamedTemporaryFile

from migration_check.structural import Json
from tools.bundle_measurement_identity import host_identity
from tools.bundle_measurement_paths import PathObservation, TrialSpec, execute_path, retain_identity
from tools.bundle_measurement_protocol import PairObservation, next_pair_count, observed_pair, pair_order
from tools.bundle_measurement_report import summarize_pairs


def write_record(path: Path, record: Mapping[str, object]) -> None:
    """Replace complete metadata atomically while leaving interrupted writes and raw trials intact."""
    try:
        with NamedTemporaryFile(mode="w", encoding="utf-8", dir=path.parent,
                                prefix=path.name + ".", suffix=".pending", delete=False) as stream:
            json.dump(record, stream, indent=2)
            stream.write("\n")
            temporary = Path(stream.name)
        temporary.replace(path)
    except (TypeError, ValueError) as error:
        raise ValueError(f"Cannot serialize campaign metadata for {path}: {error}; preserve existing evidence "
                         "and correct the record values before starting a new campaign") from error
    except OSError as error:
        raise ValueError(f"Cannot save campaign evidence at {path}: {error}; preserve the directory "
                         "and select a writable evidence root for a new campaign") from error


def new_directory(spec: TrialSpec, directory: Path) -> Path:
    """Refuse input-tree writes and existing evidence before creating any trial files."""
    output = directory.resolve()
    for root in (spec.runtime, *spec.input_roots):
        selected = root.resolve()
        if output.is_relative_to(selected):
            raise ValueError(f"Campaign output {output} is inside input root {selected}; "
                             "select an evidence directory outside runtime and source inputs")
    try:
        output.mkdir()
    except FileExistsError as error:
        raise ValueError(f"Campaign evidence directory already exists at {output}; preserve it "
                         "and select a new evidence directory") from error
    except OSError as error:
        raise ValueError(f"Cannot create campaign evidence directory {output}: {error}; "
                         "select a writable evidence root outside runtime and source inputs") from error
    return output


def execute_pair(spec: TrialSpec, number: int, directory: Path, baseline: dict[str, Json]) -> PairObservation:
    """Retain both returned paths; an interrupted path leaves a durable partial pair without invented timing."""
    first, second = pair_order(number)
    directory = new_directory(spec, directory)
    record: dict[str, object] = {"number": number, "order": [first, second], "paths": [],
        "difference_ns": None, "invalid_conditions": [], "state": "INCOMPLETE", "pending_flow": None}
    write_record(directory / "pair.json", record)
    paths: list[PathObservation] = []
    for flow in (first, second):
        record["pending_flow"] = flow
        write_record(directory / "pair.json", record)
        try:
            path = execute_path(spec, flow, directory / flow, baseline)
        except BaseException as error:
            record.update(state="INTERRUPTED" if isinstance(error, (KeyboardInterrupt, SystemExit)) else "INVALID",
                invalid_conditions=[f"{flow} did not complete: {type(error).__name__}: {error}"])
            write_record(directory / "pair.json", record)
            raise
        paths.append(path)
        record.update(paths=[asdict(item) for item in paths], pending_flow=None)
        write_record(directory / "pair.json", record)
    pair = observed_pair(number, (paths[0], paths[1]))
    write_record(directory / "pair.json", {**asdict(pair), "state": "INVALID" if pair.invalid_conditions else "COMPLETE"})
    return pair


def run_campaign(spec: TrialSpec, output: Path) -> dict[str, Json]:
    """Create new evidence; interrupted/invalid campaigns remain intact and are never overwritten or auto-pruned."""
    output = new_directory(spec, output)
    baseline = spec.identity()
    machine = host_identity()
    baseline_path = retain_identity(output / "identity.json.gz", baseline)
    context = {"format": "bundle-cold-pairs-v1", "name": spec.name, "machine": machine,
               "specification": {**asdict(spec), "runtime": str(spec.runtime), "python": str(spec.python),
                    "observer": str(spec.observer), "input_roots": list(map(str, spec.input_roots))},
               "identity": baseline_path, "state": "INCOMPLETE",
               "wall_method": "full fresh-process path wall; observation overhead included",
               "stage_method": "nested inclusive spans from the same invocations; do not sum them as path wall"}
    write_record(output / "campaign.json", context)
    pairs: list[PairObservation] = []
    summary: dict[str, Json] = summarize_pairs(pairs)
    write_record(output / "summary.json", summary)
    while len(pairs) < next_pair_count(pairs):
        number = len(pairs) + 1
        pair: PairObservation | None = None
        try:
            pair = execute_pair(spec, number, output / f"pair-{number:02d}", baseline)
            observed_machine = host_identity()
        except BaseException as error:
            state = "INTERRUPTED" if isinstance(error, (KeyboardInterrupt, SystemExit)) else "INVALID"
            condition = f"Campaign validation for pair {number} in {output} did not finish: {type(error).__name__}: {error}"
            if pair is not None:
                pair = replace(pair, difference_ns=None, invalid_conditions=(*pair.invalid_conditions, condition))
                write_record(output / f"pair-{number:02d}" / "pair.json", {**asdict(pair), "state": state})
                pairs.append(pair)
            summary = {**summarize_pairs(pairs), "status": state, "unfinished_pair": number,
                "invalid_pairs": {str(number): [condition]}, "decision": "preserve all evidence; start a new campaign"}
            context.update(state=state, stopped_pair=number, condition=condition, completed_pairs=len(pairs))
            write_record(output / "summary.json", summary)
            write_record(output / "campaign.json", context)
            raise
        changed = observed_machine != machine
        if changed:
            condition = f"Machine identity changed after pair {number} in {output}; preserve all raw trials " + (
                "and start a new campaign in a new evidence directory")
            pair = replace(pair, difference_ns=None, invalid_conditions=(*pair.invalid_conditions, condition))
            write_record(output / f"pair-{number:02d}" / "pair.json", {
                **asdict(pair), "state": "INVALID", "machine_after": observed_machine})
        pairs.append(pair)
        summary = summarize_pairs(pairs)
        write_record(output / "summary.json", summary)
        context.update(state=summary["status"], completed_pairs=len(pairs))
        write_record(output / "campaign.json", context)
        if changed:
            raise ValueError(condition)
        if pair.invalid_conditions:
            break
    return summary
