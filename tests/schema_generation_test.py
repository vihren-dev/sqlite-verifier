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
        emissions.append(sql_inputs(schema, script, ExecutionProfile(version)))
    assert emissions[0].replace(".sqlite351", ".sqlite346") == emissions[1], "Shared syntax changed meaning"
    literal_schema = starting_schema(parse(parser,
        b'CREATE TABLE ledger(version BIGINT PRIMARY KEY, label TEXT, stamp TIMESTAMP, ok BOOLEAN, data BLOB);',
        'literal-schema.sql', version))
    literal_script = statements(parse(parser,
        b"BEGIN; INSERT INTO ledger(version,label,stamp,ok,data) "
        b"VALUES(7,'shell','2026-09-25 00:00:00',1,X'00ff'); COMMIT; "
        b"UPDATE ledger SET ok=-1 WHERE version=7;", 'literal-writes.sql', version))
    literal_source = sql_inputs(literal_schema, literal_script, ExecutionProfile('3.46.0'))
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
        source.write_text(literal_source + """
example : Generated.profile = .sqlite346 := rfl
example : Generated.script.length = 4 := by decide +kernel
example : Generated.nextSchema = Generated.startSchema := rfl
example : SqliteVerifier.SupportedSql Generated.startSchema Generated.script
    Generated.startSchema.emptyDatabase := by constructor <;> decide +kernel
example : (match SqliteVerifier.runSql Generated.script Generated.startSchema.emptyDatabase with
    | .success database => (database "ledger").map (fun table =>
        table.rows.map (fun row => (row.rowid, row.values[3]?))) = some [(1, some (.integer (-1)))]
    | _ => False) := by rfl
""")
        result = subprocess.run(['lake', 'env', 'lean', str(source)], cwd=ROOT,
                                capture_output=True, text=True, timeout=30)
        assert result.returncode == 0, result.stdout + result.stderr
    print("schema generation: both native profiles agree; rich emitted records checked by Lean kernel")


if __name__ == '__main__':
    main()
