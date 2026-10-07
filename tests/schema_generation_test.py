"""Check profile-equivalent frontend emission and concrete Lean kernel properties independently."""

from collections.abc import Callable
from pathlib import Path
import os

import pytest

from belay.sqlite.profiles import ExecutionProfile
from migration_check.lean_inputs import schema_inputs, sql_inputs
from belay.sqlite.sql_tree import parse
from belay.sqlite.translate import starting_schema, statements
from tests.sql_fixtures import RICH_BASELINE
from tests.runtime_support import CommandResult

pytestmark = [pytest.mark.integration, pytest.mark.parser, pytest.mark.requires_native]
RICH_ASSERTIONS = """
open SqliteVerifier
example : Generated.startSchema.all (fun t => supportedProperties t.columns t.properties) = true := by
  decide +kernel
example : Generated.startSchema.all (fun t => supportedColumns t.columns) = true := by decide +kernel
example : Generated.nextSchema.lookupProperties "events" =
  Generated.startSchema.lookupProperties "events" := by decide +kernel
example : (Generated.startSchema.lookup "events").bind (fun cs => cs.head?.map Column.notNull) = some false := by
  decide +kernel
"""
LITERAL_ASSERTIONS = """
example : Generated.profile = .sqlite346 := rfl
example : Generated.script.length = 4 := by decide +kernel
example : Generated.nextSchema = Generated.startSchema := rfl
example : SqliteVerifier.SupportedSql Generated.startSchema Generated.script
    Generated.startSchema.emptyDatabase := by constructor <;> decide +kernel
example : (match SqliteVerifier.runSql Generated.script Generated.startSchema.emptyDatabase with
    | .success database => (database "ledger").map (fun table =>
        table.rows.map (fun row => (row.rowid, row.values[3]?))) = some [(1, some (.integer (-1)))]
    | _ => False) := by rfl
"""


def rich_source(runtime: Path, version: str) -> tuple[str, str]:
    """Emit the same rich baseline and nullable ADD from the selected parser release."""
    filename = "sqlite-parser" if version == "3.51.0" else "sqlite-parser-3.46.0"
    parser = runtime / "build" / filename
    schema = starting_schema(parse(parser, RICH_BASELINE.encode(), "baseline.sql", version))
    script = statements(parse(parser, b"ALTER TABLE events ADD extra TEXT;", "migration.sql", version))
    return schema_inputs(schema), sql_inputs(schema, script, ExecutionProfile(version))


def test_profile_emission_equivalence(runtime_root: Path) -> None:
    """The same syntax has identical generated meaning apart from its sealed SQLite constructor."""
    _, current = rich_source(runtime_root, "3.51.0")
    _, older = rich_source(runtime_root, "3.46.0")
    assert "def profile : ExecutionProfile := .sqlite351" in current
    assert current.replace(".sqlite351", ".sqlite346") == older, "Shared syntax changed meaning"


def check_source(source: str, tmp_path: Path, lean_sysroot: Path, lean_library: Path,
                 command_runner: Callable[..., CommandResult]) -> None:
    """Kernel-check fresh generated source using the explicitly selected immutable library."""
    proof = tmp_path / "GeneratedSchema.lean"
    proof.write_text(source)
    checked = command_runner([str(lean_sysroot / "bin/lean"), str(proof)], cwd=tmp_path,
                             timeout=30, environment={**os.environ, "LEAN_PATH": str(lean_library)})
    assert checked.returncode == 0, checked.diagnostic()


@pytest.mark.kernel
@pytest.mark.requires_lean
def test_rich_schema_kernel_properties(runtime_root: Path, tmp_path: Path, lean_sysroot: Path,
                                      lean_library: Path, command_runner: Callable[..., CommandResult]) -> None:
    """Supported rich columns/index metadata and nullable ADD emission satisfy concrete kernel assertions."""
    schema, sql = rich_source(runtime_root, "3.51.0")
    check_source(schema + sql.removeprefix("import SchemaInputs\n") + RICH_ASSERTIONS,
                 tmp_path, lean_sysroot, lean_library, command_runner)


@pytest.mark.kernel
@pytest.mark.requires_lean
def test_literal_write_kernel_properties(runtime_root: Path, tmp_path: Path, lean_sysroot: Path,
                                        lean_library: Path, command_runner: Callable[..., CommandResult]) -> None:
    """Explicit transaction/literal operations bind the older profile and produce the exact stored integer."""
    parser = runtime_root / "build/sqlite-parser-3.46.0"
    schema = starting_schema(parse(parser,
        b"CREATE TABLE ledger(version BIGINT PRIMARY KEY, label TEXT, stamp TIMESTAMP, ok BOOLEAN, data BLOB);",
        "literal-schema.sql", "3.46.0"))
    script = statements(parse(parser,
        b"BEGIN; INSERT INTO ledger(version,label,stamp,ok,data) "
        b"VALUES(7,'shell','2026-09-25 00:00:00',1,X'00ff'); COMMIT; "
        b"UPDATE ledger SET ok=-1 WHERE version=7;", "literal-writes.sql", "3.46.0"))
    sql = sql_inputs(schema, script, ExecutionProfile("3.46.0"))
    check_source(schema_inputs(schema) + sql.removeprefix("import SchemaInputs\n") + LITERAL_ASSERTIONS,
                 tmp_path, lean_sysroot, lean_library, command_runner)
