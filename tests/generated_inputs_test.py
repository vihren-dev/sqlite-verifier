"""ADR 0003 P3 and ADR 0008: the generated inputs are the resolution of the structural record.

The resolver (`packages/verifier-gate/Resolver.lean`) writes `SchemaInputs` and
`SqlInputs` from the record. The bundle checker
(`packages/verifier-gate/BundleChecker.lean`, `packages/sqlite-verifier/GateInputs.lean`)
resolves the record again; in `--parity` mode it compares its constructed
declarations with the compiled resolver output. A changed record or a changed compiled module is rejected.
"""

from collections.abc import Callable
import json
import os
from pathlib import Path

import pytest

from belay.sqlite.located import Json
from belay.sqlite.profiles import profile
from migration_check.project_config import load as load_config
from belay.sqlite.sql_tree import Tree
from belay.sqlite.syntax import script_record, statements
from migration_check.contract import Contract, compile_trusted
from tests.runtime_support import CommandResult, run_command
from tests.sql_fixtures import RICH_BASELINE

pytestmark = [pytest.mark.integration, pytest.mark.kernel, pytest.mark.requires_lean, pytest.mark.requires_native]
LEDGER = "CREATE TABLE ledger(version BIGINT PRIMARY KEY, label TEXT, stamp TIMESTAMP, ok BOOLEAN, data BLOB);"
WRITES = ("BEGIN; INSERT INTO ledger(version,label,stamp,ok,data) "
          "VALUES(-9223372036854775808,'can''t λ \\ \"q\"','2026-09-25 00:00:00',NULL,X'00ff7f80'); COMMIT; "
          "INSERT INTO ledger(version,label,stamp,ok,data) VALUES(9223372036854775807,'',NULL,1,X''); "
          "UPDATE ledger SET ok=-1 WHERE version=7; BEGIN; UPDATE ledger SET label=NULL WHERE version=0; ROLLBACK;")


Source = Callable[[Path], tuple[str, str, str]]
"""Schema SQL, migration SQL and SQLite profile of one case, given the runtime under test."""


def example(name: str) -> Source:
    """A case shipped in the selected runtime, with the inputs its `belay.toml` names."""
    def read(runtime: Path) -> tuple[str, str, str]:
        """Load the case's configuration from the runtime's own examples."""
        examples = runtime / "examples"
        config = load_config(examples / name / "belay.toml", examples)
        return config.schema.read_text(), config.migration.read_text(), config.profile
    return read


def literal(schema_sql: str, migration_sql: str, version: str) -> Source:
    """A hand-written schema and migration, under the given profile."""
    return lambda _runtime: (schema_sql, migration_sql, version)


CASES: dict[str, Source] = {
    "add_column_then_table": example("add_column_then_table"),
    "table_then_column": example("table_then_column"),
    "refutation_unchanged_invoices": example("missing_required_column"),
    "allowed_failure": example("allowed_failure"),
    "atuin_3_46": example("atuin"),
    "literal_writes_and_transactions": literal(LEDGER, WRITES, "3.46.0"),
    "rich_schema_nullable_add": literal(RICH_BASELINE, "ALTER TABLE events ADD extra TEXT;", "3.51.0"),
    "unchanged_schema": literal(LEDGER, "BEGIN; COMMIT;", "3.51.0"),
    "unicode_names": literal('CREATE TABLE "Café"("Имя" TEXT, n INTEGER);',
                             'ALTER TABLE "Café" ADD "💡" BLOB; CREATE TABLE extra(r REAL, n NUMERIC);', "3.51.0"),
    "prepare_errors": literal(LEDGER, "ALTER TABLE absent ADD x TEXT; CREATE TABLE LEDGER(x); "
                              "INSERT INTO ledger(version, missing) VALUES (1, 2);", "3.51.0"),
}


def resolver_sources(runtime_root: Path, record: dict[str, Json], workspace: Path) -> tuple[str, str]:
    """Run the runtime's resolver on the record and return the generated module sources."""
    record_path, output = workspace / "record.json", workspace / "generated"
    record_path.write_text(json.dumps(record))
    output.mkdir()
    result = run_command([str(runtime_root / ".lake/build/bin/migration-resolver"), str(record_path), str(output)],
                         cwd=workspace, timeout=30)
    assert result.returncode == 0 and json.loads(result.stdout) == {"status": "resolved"}, result.diagnostic()
    return (output / "SchemaInputs.lean").read_text(), (output / "SqlInputs.lean").read_text()


@pytest.fixture
def parity(runtime_root: Path, lean_sysroot: Path, lean_libraries: tuple[Path, Path], tmp_path: Path,
           parse_sql: Callable[..., Tree]) -> Callable[..., CommandResult]:
    """Compile the resolver's modules, then ask the bundle checker to compare its construction."""
    def check(schema_sql: str, migration_sql: str, version: str,
              mutate: Callable[[dict[str, Json]], object] | None = None) -> CommandResult:
        """Return the checker's `--parity` result, optionally for a record changed after compilation."""
        record = script_record(profile(version), statements(parse_sql(schema_sql, version)),
                               statements(parse_sql(migration_sql, version)))
        workspace, trusted, approved = tmp_path / "work", tmp_path / "trusted", tmp_path / "approved"
        for directory in (workspace, trusted, approved):
            directory.mkdir()
        schema_source, sql_source = resolver_sources(runtime_root, record, workspace)
        compile_trusted(contract=Contract({}, (), frozenset()), approved_sources=approved,
                        schema_inputs=schema_source, sql_inputs=sql_source, trusted=trusted, sysroot=lean_sysroot,
                        libraries=tuple(path.resolve() for path in lean_libraries), workspace=workspace)
        if mutate is not None:
            mutate(record)
        generated = tmp_path / "generated.json"
        generated.write_text(json.dumps(record))
        return run_command([str(runtime_root / ".lake/build/bin/migration-bundle-checker"), "--parity",
                            *[str(path.resolve()) for path in lean_libraries], str(trusted), str(generated)],
                           cwd=tmp_path, timeout=60, environment={**os.environ, "LEAN_SYSROOT": str(lean_sysroot)})
    return check


@pytest.mark.parametrize("name", CASES)
def test_constructed_declarations_match_resolver(parity: Callable[..., CommandResult], runtime_root: Path,
                                                 name: str) -> None:
    """The checker's own resolution equals the compiled resolver output, declaration by declaration."""
    schema_sql, migration_sql, version = CASES[name](runtime_root)
    result = parity(schema_sql, migration_sql, version)
    assert result.returncode == 0, result.diagnostic()


@pytest.mark.parametrize("change,diagnostic", [
    (lambda record: record["schema"][0]["createTable"].update(name="other"),
     "differs from the resolution of the script record: Generated.schema"),
    (lambda record: record.update(version=1), "only version 3 is supported"),
    (lambda record: record.pop("script"), "bundle checker rejected"),
    (lambda record: record["script"].append("commit"), "value differs from the compiled SqlInputs: Generated.script"),
    (lambda record: record.update(release="3.46.0"),
     "differs from the resolution of the script record: Generated.profile"),
    (lambda record: record["script"].append({"createIndex": {"name": "i", "unique": False, "table": "invoices",
                                                             "columns": ["amount"]}}),
     "the script record does not resolve"),
], ids=["changed_schema", "other_version", "missing_field", "extra_statement", "other_profile", "restricted"])
def test_tampered_record_is_rejected(parity: Callable[..., CommandResult], runtime_root: Path,
                                     change: Callable[[dict[str, Json]], object], diagnostic: str) -> None:
    """A record that disagrees with the compiled inputs, is malformed, or does not resolve is rejected."""
    schema_sql, migration_sql, _version = example("add_column_then_table")(runtime_root)
    result = parity(schema_sql, migration_sql, "3.51.0", change)
    assert result.returncode == 1 and diagnostic in result.stderr, result.diagnostic()
