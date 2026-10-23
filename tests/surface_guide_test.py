"""The examples of the user guide in the product repository, as the guide writes them, over the
surface (`packages/belay`, ADR 0017, D3). Each fixture holds the examples of one section and fails
to elaborate when an example does not hold.
"""

from pathlib import Path

import pytest

from tests.runtime_support import run_command
from tests.surface_support import FIXTURES, surface_command

pytestmark = [pytest.mark.integration, pytest.mark.parser, pytest.mark.requires_lean("compiler")]


def test_guide_values_examples_hold(runtime_root: Path, tmp_path: Path) -> None:
    """The section "Values" (`Belay/Sqlite/Values.lean`): the literal coercions, the order of
    `Value.compare`, three-valued truth, `Value.store` and the named lemmas."""
    result = run_command(surface_command(runtime_root, FIXTURES / "GuideValues.lean", tmp_path), cwd=tmp_path,
                         timeout=60)
    assert result.returncode == 0, result.diagnostic()


def test_guide_databases_examples_hold(runtime_root: Path, tmp_path: Path) -> None:
    """The section "Databases" (`Belay/Sqlite/Database.lean`, `Belay/Sqlite/DbBang.lean`):
    `Database.empty`, a database of `db!`, `db.rows`, and the facts of a valid database, which
    need no hypothesis."""
    result = run_command(surface_command(runtime_root, FIXTURES / "GuideDatabases.lean", tmp_path), cwd=tmp_path,
                         timeout=60)
    assert result.returncode == 0, result.diagnostic()


def test_guide_scripts_examples_hold(runtime_root: Path, tmp_path: Path) -> None:
    """The section "Scripts" (`Belay/Sqlite/Script.lean`, `Belay/Sqlite/SqlTerm.lean`): `sql r"..."`
    gives the statements of the text in order, in plain and `#` raw strings, with no values for
    a text without parameters; `sql r"SELECT ?1"` is a function of `p1`; `Script.withValues`
    binds values, `++` with `Script.empty` is a monoid that keeps each statement's values, and a
    run reads them."""
    result = run_command(surface_command(runtime_root, FIXTURES / "GuideScripts.lean", tmp_path), cwd=tmp_path,
                         timeout=60)
    assert result.returncode == 0, result.diagnostic()


def test_sql_errors_are_at_their_position_in_the_text(runtime_root: Path, tmp_path: Path) -> None:
    """`sql r"..."` (`Belay/Sqlite/SqlTerm.lean`, `textRange` of `Belay/Sqlite/SqlLiteral.lean`) is an
    elaboration error at the byte of the SQL text where SQLite's grammar rejects it, in a plain raw
    string and in raw strings with one and three `#`, and at the statement that the translation
    refuses, with its message."""
    result = run_command(surface_command(runtime_root, FIXTURES / "ScriptErrors.lean", tmp_path), cwd=tmp_path,
                         timeout=60)
    assert result.returncode == 1, result.diagnostic()
    for position in ("11:42", "12:49", "13:49"):
        assert f"ScriptErrors.lean:{position}: error: SQLite's grammar rejects the SQL at this offset" in \
            result.stdout, result.diagnostic()
    assert "ScriptErrors.lean:14:30: error: This statement is not modeled" in result.stdout, result.diagnostic()


def test_guide_run_examples_hold(runtime_root: Path, tmp_path: Path) -> None:
    """The guide's runs (`Belay/Sqlite/Run.lean`, `Belay/Sqlite/RunLaws.lean`, the model's
    `Model/OutputRepr.lean`): "A first example", "Row order" and the runs of "Scripts", with the
    outputs that `#eval` shows and the facts that the kernel checks; `sql! shop r"..."`
    (`Belay/Sqlite/SqlBang.lean`) gives the script of `sql r"..."`; and `db!`
    (`Belay/Sqlite/DbBang.lean`) gives the database that the run of its text gives, with a proof
    that uses only Lean's standard axioms."""
    result = run_command(surface_command(runtime_root, FIXTURES / "GuideRuns.lean", tmp_path), cwd=tmp_path,
                         timeout=120)
    assert result.returncode == 0, result.diagnostic()


def test_guide_query_examples_hold(runtime_root: Path, tmp_path: Path) -> None:
    """The guide's "Queries as propositions" over one database (`Belay/Sqlite/Queries.lean`,
    `Belay/Sqlite/QueryLaws.lean`, the model's `Model/QueryOutputs.lean`): `Holds`, `Empty` and `Fails` hold or fail by `decide`, a query
    with `LIMIT 1` and no `ORDER BY` holds for each result, `Empty` of an `EXCEPT` query (ADR 0019,
    D3) holds or fails by `decide`, a query that reads the clock satisfies
    none of the three, and a script that is not one read-only statement is an error at the term."""
    result = run_command(surface_command(runtime_root, FIXTURES / "GuideQueries.lean", tmp_path), cwd=tmp_path,
                         timeout=60)
    assert result.returncode == 0, result.diagnostic()


def test_sql_command_shows_tables(runtime_root: Path, tmp_path: Path) -> None:
    """`#sql db r"..."` (`Belay/Sqlite/SqlCommand.lean`, the model's `Model/OutputTable.lean`):
    the guide's table of "A first example", and for each other output its text: the count of
    changed rows, the names of RETURNING columns, an error, a query without rows, NULL, REAL and
    BLOB cells, each result of a query that depends on the row order, the end of a run, and a
    syntax error at its position."""
    result = run_command(surface_command(runtime_root, FIXTURES / "GuideTables.lean", tmp_path), cwd=tmp_path,
                         timeout=60)
    assert result.returncode == 0, result.diagnostic()


def test_run_examples_hold(runtime_root: Path, tmp_path: Path) -> None:
    """The run of `db.run` (`Belay/Sqlite/Run.lean`, `Belay/Sqlite/ProgramRun.lean`, over the model's
    `runScriptFrom`), the facts of `Belay/Sqlite/Database.lean` and the display of outputs: errors
    that do not stop the run,
    transactions, `PRAGMA foreign_keys`, a table that an earlier statement drops, statements that
    the model does not describe, row order, the facts of a valid database without a hypothesis,
    and the check that keeps the start database and gives no value when the database at the end is
    not valid."""
    result = run_command(surface_command(runtime_root, FIXTURES / "RunExamples.lean", tmp_path), cwd=tmp_path,
                         timeout=120)
    assert result.returncode == 0, result.diagnostic()


def test_sql_bang_errors_are_at_the_name_or_node(runtime_root: Path, tmp_path: Path) -> None:
    """`sql! db r"..."` (`Belay/Sqlite/SqlBang.lean`, `Belay/Sqlite/SqlDiagnostics.lean`) shows
    SQLite's prepare errors at the name, or at the statement when the text writes the name more
    than once, the first model restriction at its node, and a grammar error at its offset. The
    fixture checks each message and position with `#guard_msgs (positions := true)`."""
    result = run_command(surface_command(runtime_root, FIXTURES / "SqlBangErrors.lean", tmp_path), cwd=tmp_path,
                         timeout=60)
    assert result.returncode == 0, result.diagnostic()


def test_sql_bang_database_errors_are_at_the_term(runtime_root: Path, tmp_path: Path) -> None:
    """The database term of `sql! db r"..."` (`Belay/Sqlite/EvalDatabase.lean`): an error at the
    term when it depends on a variable, is not fully known or is noncomputable, a value for a
    local definition, and no second error when the term uses a definition with an error, also
    through another definition. The fixture checks each message and position with
    `#guard_msgs (positions := true)`."""
    result = run_command(surface_command(runtime_root, FIXTURES / "SqlBangDatabaseErrors.lean", tmp_path),
                         cwd=tmp_path, timeout=60)
    assert result.returncode == 0, result.diagnostic()


def test_sql_diagnostics_are_byte_ranges_of_the_text(runtime_root: Path, tmp_path: Path) -> None:
    """The pure part of `sql!`: `Span.select` and `Span.leaves` (`Translation/Located.lean`), the name
    search `nameRange?` and `scriptDiagnostics` (`Belay/Sqlite/SqlDiagnostics.lean`), and
    `PrepareError.name?` of the model, over hand-built spans and translated texts, where a leaf
    can cover a whole expression."""
    result = run_command(surface_command(runtime_root, FIXTURES / "SqlDiagnosticsChecks.lean", tmp_path),
                         cwd=tmp_path, timeout=60)
    assert result.returncode == 0, result.diagnostic()


def test_db_bang_errors_are_at_the_statement_or_name(runtime_root: Path, tmp_path: Path) -> None:
    """`db! r"..."` (`Belay/Sqlite/DbBang.lean`, `Belay/Sqlite/DbDiagnostics.lean`) shows a statement
    that fails at the statement, each one when several fail, a prepare error at the name, a model
    restriction at its node and a clock read at the statement with no error after them, a
    grammar error at its offset, a refused form at the statement, and an open transaction at the
    end of the text, but not after a run that ends early; `sql!` on a failed `db!` gives no
    second error. The fixture checks each
    message and position with `#guard_msgs (positions := true)`."""
    result = run_command(surface_command(runtime_root, FIXTURES / "DbBangErrors.lean", tmp_path), cwd=tmp_path,
                         timeout=60)
    assert result.returncode == 0, result.diagnostic()


def test_db_bang_names_the_constraint_of_an_insert(runtime_root: Path, tmp_path: Path) -> None:
    """`db! r"..."` names the constraint that a plain INSERT or CREATE UNIQUE INDEX fails with
    SQLite 3.51's message (`constraintMessage` of `Model/ExecutionMessages.lean`, from
    `failingConstraints` of `Model/FailingConstraints.lean`, through
    `Belay/Sqlite/DbDiagnostics.lean`): NOT NULL in table order, the order of the unique keys, the
    columns or the index of a key, CHECK labels, STRICT types and NOT NULL before CHECK, and both
    candidates when a PRIMARY KEY and a UNIQUE constraint fail. The fixture has the native texts
    and checks each message and position with `#guard_msgs (positions := true)`."""
    result = run_command(surface_command(runtime_root, FIXTURES / "DbBangConstraintMessages.lean", tmp_path),
                         cwd=tmp_path, timeout=60)
    assert result.returncode == 0, result.diagnostic()


def test_db_bang_names_the_constraint_of_other_writes(runtime_root: Path, tmp_path: Path) -> None:
    """`db! r"..."` names the constraint that an INSERT with ON CONFLICT or an algorithm, or an
    UPDATE, fails with SQLite 3.51's message, and each candidate for an UPDATE of several rows
    (`failingConstraints` of `Model/FailingConstraints.lean`, `Catalog.updateReport` of
    `Model/UpdateFailure.lean`); it gives SQLite's text for a CHECK of ADD COLUMN, and
    `triggerOrKeyConstraintMessage` for a write that can fire a trigger or that checks foreign keys. The
    fixture checks each message and position with `#guard_msgs (positions := true)`."""
    result = run_command(surface_command(runtime_root, FIXTURES / "DbBangConstraintWrites.lean", tmp_path),
                         cwd=tmp_path, timeout=60)
    assert result.returncode == 0, result.diagnostic()


def test_db_bang_names_column_failures_in_sqlite_order(runtime_root: Path, tmp_path: Path) -> None:
    """`db!` names the constraint that an INSERT or an UPDATE fails in SQLite 3.51's order of checks
    (`Model/RowCheckOrder.lean`, `tableFailures` of `Model/TableFailure.lean`, `changedRowFailures`
    of `Model/UpdateFailure.lean`): the early types of the ordinary and VIRTUAL columns in a table
    with a generated column, NOT NULL, the late types before CHECK or after the rowid, and the
    keys; an UPDATE or a DO UPDATE runs only the CHECK constraints that read a changed column
    (`CatalogTable.updateRunsChecks`); for an UPDATE of several rows, each failure that SQLite's order of the rows can make
    first. The fixture checks each message and position with `#guard_msgs (positions := true)`;
    each expected text is the native shell's."""
    result = run_command(surface_command(runtime_root, FIXTURES / "DbBangCheckOrder.lean", tmp_path),
                         cwd=tmp_path, timeout=60)
    assert result.returncode == 0, result.diagnostic()

def test_db_bang_messages_and_failing_atoms_are_computed(runtime_root: Path, tmp_path: Path) -> None:
    """The model functions of the errors of `db!`: `ExecutionError.message`
    (`Model/ExecutionMessages.lean`) for each constructor, `LiteralData.tableFailures` and
    `keyCandidates` on hand-built tables and keys, `Resolved.Statement.writeRules` of resolved
    INSERTs with and without a trigger, `Database.failingAtom?`
    (`Model/ValidityFailure.lean`) on plain databases with a NULL in a NOT NULL column, a duplicate
    key, a duplicate rowid, a failed CHECK, a value that does not fit a STRICT type, both of these,
    and no rows list; `ValidityAtom.name` for each atom; and the term or the error that names the
    atom (`databaseTerm` and `invalidDatabaseMessage` of `Belay/Sqlite/DbBang.lean`)."""
    result = run_command(surface_command(runtime_root, FIXTURES / "DbBangChecks.lean", tmp_path), cwd=tmp_path,
                         timeout=60)
    assert result.returncode == 0, result.diagnostic()
