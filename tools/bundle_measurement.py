"""Select a shipped example for the retained cold-pair campaign; owner review follows every result."""

import argparse
from collections.abc import Mapping, Sequence
from dataclasses import dataclass
import json
import os
from pathlib import Path
import sys
from typing import Literal

from tools.bundle_measurement_campaign import run_campaign
from tools.bundle_measurement_paths import TrialSpec


@dataclass(frozen=True)
class ExampleSelection:
    """Keep each documented source layout, identity roots and expected result in one case definition."""

    approved: str
    candidate: str
    schema: str
    input_roots: tuple[str, ...]
    profile: str
    expected_status: Literal["VERIFIED", "VIOLATED"]


NAMED_CASES: Mapping[str, ExampleSelection] = {
    "small-success": ExampleSelection("approved", "add_column_then_table", "approved/schema.sql",
        ("approved", "add_column_then_table"), "3.51.0", "VERIFIED"),
    "checked-refutation": ExampleSelection("approved", "missing_required_column", "approved/schema.sql",
        ("approved", "missing_required_column"), "3.51.0", "VIOLATED"),
    "atuin": ExampleSelection("atuin/approved", "atuin", "atuin/schema.sql", ("atuin",), "3.46.0", "VERIFIED"),
}
"""The three approved comparison examples; custom requests still use TrialSpec directly."""


def required_file(path: Path, *, executable: bool = False) -> Path:
    """Refuse incomplete selected inputs before the campaign creates any evidence directory."""
    if not path.is_file() or (executable and not os.access(path, os.X_OK)):
        raise ValueError(f"Required campaign input is missing or unusable at {path}; "
                         "select a complete installed runtime and its executable Python")
    return path.resolve(strict=True)


def named_trial_spec(name: str, *, runtime: Path, python: Path, timeout_ns: int) -> TrialSpec:
    """Build ordinary public CLI arguments over the flexible primitive using installed example sources."""
    if name not in NAMED_CASES:
        raise ValueError(f"Unknown campaign case {name!r}; select one of {', '.join(NAMED_CASES)}")
    if not runtime.is_dir():
        raise ValueError(f"Campaign runtime directory is missing at {runtime}; select a complete installation")
    runtime = runtime.resolve(strict=True)
    required_file(runtime / "bin/migration-check", executable=True)
    python = required_file(python, executable=True)
    declared = required_file(runtime / "python-path").read_text(encoding="utf-8").strip()
    if not Path(declared).is_absolute():
        raise ValueError(f"Declared interpreter path in {runtime / 'python-path'} is not absolute; "
                         "repair the installation before starting a campaign")
    if required_file(Path(declared), executable=True) != python:
        raise ValueError(f"Selected Python {python} differs from {runtime / 'python-path'}; "
                         "supply the installed runtime's declared interpreter")
    selection = NAMED_CASES[name]
    examples = runtime / "examples"
    approved, candidate, schema = examples / selection.approved, examples / selection.candidate, examples / selection.schema
    common_roles = (("schema", schema), ("requirements", approved / "Requirements.lean"),
                    ("interpretation", approved / "Interpretation.lean"), ("migration", candidate / "migration.sql"))
    candidate_roles = (("next-interpretation", candidate / "NextInterpretation.lean"),
                       ("proofs", candidate / "Proofs.lean"))
    common = ("--profile", selection.profile, "--format", "json", *(part for role, path in common_roles
              for part in ("--" + role, str(required_file(path)))))
    proposed = tuple(part for role, path in candidate_roles for part in ("--" + role, str(required_file(path))))
    roots = tuple(examples / relative for relative in selection.input_roots)
    observer = required_file(Path(__file__).with_name("bundle_measurement_child.py"))
    return TrialSpec(name, runtime, python, observer, roots, common, proposed, selection.expected_status, timeout_ns)


def main(values: Sequence[str]) -> int:
    """Run one explicitly selected campaign into new evidence; completion never grants cutover acceptance."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--case", choices=tuple(NAMED_CASES), required=True)
    parser.add_argument("--runtime", type=Path, required=True, help="Complete installed verifier directory")
    parser.add_argument("--python", type=Path, required=True, help="Executable declared by runtime/python-path")
    parser.add_argument("--output", type=Path, required=True, help="New evidence directory outside the runtime")
    parser.add_argument("--timeout-seconds", type=int, required=True, help="Positive common whole-path deadline")
    options = parser.parse_args(values)
    if options.timeout_seconds <= 0:
        parser.error("--timeout-seconds must be a positive number of seconds; supply a positive whole-path deadline")
    try:
        spec = named_trial_spec(options.case, runtime=options.runtime, python=options.python,
                                timeout_ns=options.timeout_seconds * 1_000_000_000)
        summary = run_campaign(spec, options.output)
    except (ValueError, OSError) as error:
        parser.error(str(error))
    print(json.dumps(summary, indent=2))
    return 0 if summary["status"] == "COMPLETE" else 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
