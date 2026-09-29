"""Run bounded fixed-seed generation and keep its exact structural case inputs."""

import argparse
import json
from pathlib import Path

from conformance.state_machine import generate


def main() -> None:
    """Long runs are explicit and never selected by the ordinary test target."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runtime-root", type=Path, default=Path("build/conformance"))
    parser.add_argument("--output", type=Path, default=Path("build/generated"))
    parser.add_argument("--examples", type=int, default=20)
    parser.add_argument("--steps", type=int, default=8)
    parser.add_argument("--seed", type=int, default=4004)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    report = {"seed": args.seed, "maxExamplesPerMode": args.examples, "maxSteps": args.steps, "modes": {}}
    records = []
    for mode in (False, True):
        counts, cases = generate(args.runtime_root.resolve(), error_seeking=mode,
            examples=args.examples, steps=args.steps, fixed_seed=args.seed)
        report["modes"]["error-seeking" if mode else "well-scoped"] = counts
        records.extend(cases)
    (args.output / "cases.jsonl").write_text("".join(json.dumps(case) + "\n" for case in records))
    (args.output / "report.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report))


if __name__ == "__main__":
    main()
