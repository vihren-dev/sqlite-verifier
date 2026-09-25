"""Kernel-check rich frontend emission and native-version selection independently of proofs."""

from pathlib import Path
import subprocess
import sys
from tempfile import TemporaryDirectory

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

from migration_check.sql_model import sql_inputs
from migration_check.profiles import ExecutionProfile
from migration_check.sql_tree import parse
from migration_check.translate import starting_schema, statements
from tests.test_schema_translation import BASELINE


def main() -> None:
    """Use both actual grammar binaries and check all emitted properties in Lean's kernel."""
    emissions: list[str] = []
    for version, filename in (("3.51.0", "sqlite-parser"), ("3.46.0", "sqlite-parser-3.46.0")):
        parser = ROOT / "build" / filename
        schema = starting_schema(parse(parser, BASELINE.encode(), "baseline.sql", version))
        script = statements(parse(parser, b'ALTER TABLE events ADD extra TEXT;', "migration.sql", version))
        emissions.append(sql_inputs(schema, script))
    assert emissions[0] == emissions[1], "Shared supported syntax has divergent structured meanings"
    runner = ExecutionProfile('3.46.0', 20, b'new column', ())
    runner_source = sql_inputs(schema, script, runner, b'ALTER TABLE events ADD extra TEXT;')
    assertion = """
open SqliteVerifier
example : Generated.startSchema.all (fun t => supportedProperties t.columns t.properties) = true := by
  decide +kernel
example : Generated.startSchema.all (fun t => supportedColumns t.columns) = true := by decide +kernel
example : Generated.nextSchema.lookupProperties "events" =
  Generated.startSchema.lookupProperties "events" := by decide +kernel
example : (Generated.startSchema.lookup "events").bind (fun cs => cs.head?.map Column.notNull) = some false := by
  decide +kernel
"""
    with TemporaryDirectory(prefix="schema-generation-") as temporary:
        source = Path(temporary) / "GeneratedSchema.lean"
        source.write_text(emissions[0] + assertion)
        result = subprocess.run(['lake', 'env', 'lean', str(source)], cwd=ROOT,
                                capture_output=True, text=True, timeout=30)
        assert result.returncode == 0, result.stdout + result.stderr
        source.write_text(runner_source + """
example : (match Generated.profile with
  | .sqlite346Sqlx config => config.migration.version == 20 && config.migration.checksum.length == 48
  | _ => false) = true := by decide +kernel
""")
        result = subprocess.run(['lake', 'env', 'lean', str(source)], cwd=ROOT,
                                capture_output=True, text=True, timeout=30)
        assert result.returncode == 0, result.stdout + result.stderr
    print("schema generation: both native profiles agree; rich emitted records checked by Lean kernel")


if __name__ == '__main__':
    main()
