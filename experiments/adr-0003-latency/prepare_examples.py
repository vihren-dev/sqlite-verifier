"""Keep the production compiler's trusted and candidate `.olean` outputs for each example.

Usage: python3 experiments/adr-0003-latency/prepare_examples.py
Writes build/adr-0003-latency/compiled/<case>/{trusted,candidate}.
"""

import shutil
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from cases import CASES, ROOT, WORK  # noqa: E402

sys.path.insert(0, str(ROOT))
from migration_check.compile import compile_project  # noqa: E402
from migration_check.profiles import profile  # noqa: E402
from migration_check.runtime import Runtime  # noqa: E402
from migration_check.sql_model import schema_inputs, sql_inputs  # noqa: E402
from migration_check.sql_tree import parse  # noqa: E402
from migration_check.translate import starting_schema, statements  # noqa: E402


def compile_case(name: str, schema: Path, approved: Path, candidate: Path, version: str) -> Path:
    """Run the same staged compilation as `verify`, into a workspace that is kept."""
    selected = profile(version)
    runtime = Runtime.locate(selected.engine)
    start = starting_schema(parse(runtime.parser, schema.read_bytes(), "schema.sql", version))
    script = statements(parse(runtime.parser, (candidate / "migration.sql").read_bytes(), "migration.sql", version))
    workspace = WORK / "compiled" / name
    shutil.rmtree(workspace, ignore_errors=True)
    workspace.mkdir(parents=True)
    compile_project(sysroot=runtime.sysroot, library=runtime.library,
                    requirements=approved / "Requirements.lean", interpretation=approved / "Interpretation.lean",
                    next_interpretation=candidate / "NextInterpretation.lean", proofs=candidate / "Proofs.lean",
                    schema_inputs=schema_inputs(start), sql_inputs=sql_inputs(start, script, selected),
                    workspace=workspace)
    return workspace


if __name__ == "__main__":
    for case in CASES:
        print(compile_case(case.name, case.schema, case.approved, case.candidate, case.profile))
