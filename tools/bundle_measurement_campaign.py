"""Retain every alternating cold pair and extend the same nine to 25 only when the policy requires it."""

from dataclasses import asdict
import json
from pathlib import Path

from migration_check.structural import Json
from tools.bundle_measurement_identity import host_identity
from tools.bundle_measurement_paths import TrialSpec, execute_path, retain_identity
from tools.bundle_measurement_protocol import PairObservation, next_pair_count, observed_pair, pair_order
from tools.bundle_measurement_report import summarize_pairs


def execute_pair(spec: TrialSpec, number: int, directory: Path, baseline: dict[str, Json]) -> PairObservation:
    """Run both ordered paths even when one fails, retaining the original raw pair without resampling."""
    directory.mkdir()
    first, second = pair_order(number)
    paths = (execute_path(spec, first, directory / first, baseline),
             execute_path(spec, second, directory / second, baseline))
    pair = observed_pair(number, paths)
    with (directory / "pair.json").open("x") as stream:
        json.dump(asdict(pair), stream, indent=2)
        stream.write("\n")
    return pair


def run_campaign(spec: TrialSpec, output: Path) -> dict[str, Json]:
    """Create new evidence; interrupted/invalid campaigns remain intact and are never overwritten or auto-pruned."""
    if any(output.resolve().is_relative_to(root.resolve()) for root in (spec.runtime, *spec.input_roots)):
        raise ValueError("Campaign output is inside selected runtime/source inputs")
    output.mkdir()
    baseline = spec.identity()
    machine = host_identity()
    baseline_path = retain_identity(output / "identity.json.gz", baseline)
    context = {"format": "bundle-cold-pairs-v1", "name": spec.name, "machine": machine,
               "specification": {**asdict(spec), "runtime": str(spec.runtime), "python": str(spec.python),
                    "observer": str(spec.observer), "input_roots": list(map(str, spec.input_roots))},
               "identity": baseline_path, "wall_method": "full fresh-process path wall; observation overhead included",
               "stage_method": "nested inclusive spans from the same invocations; do not sum them as path wall"}
    (output / "campaign.json").write_text(json.dumps(context, indent=2) + "\n")
    pairs: list[PairObservation] = []
    summary: dict[str, Json] = summarize_pairs(pairs)
    (output / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    while len(pairs) < next_pair_count(pairs):
        number = len(pairs) + 1
        pair = execute_pair(spec, number, output / f"pair-{number:02d}", baseline)
        if host_identity() != machine:
            raise ValueError("Machine identity changed during campaign; preserve every raw trial and report the condition")
        pairs.append(pair)
        summary = summarize_pairs(pairs)
        (output / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
        if pair.invalid_conditions:
            break
    return summary
