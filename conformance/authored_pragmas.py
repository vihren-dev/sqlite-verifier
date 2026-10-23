"""Authored coverage cases of pragmas as statements (ADR 0019, slice 2;
plans/20261023-pragmas.task.md).

The cases follow the "Tests" list of the task: `ok` of both check pragmas after writes of each
constraint kind, also with a limit and a table name; `foreign_key_check` with foreign keys off
over each kind of parent key, with and without a table name over one failing table; the
mismatch and the missing-table errors; `table_info` and `foreign_key_list` of each column and
key form, and their table-valued forms with `ORDER BY`, `WHERE` and a join; and
`recursive_triggers` under a profile that has the setting on. The cases are in
`conformance.authored_pragma_checks` and `conformance.authored_pragma_schema`. Native SQLite is
the only source of outcomes.
"""

from dataclasses import dataclass
from pathlib import Path
from tempfile import TemporaryDirectory

from conformance.authored_resolution import profile as default_profile
from conformance.case_format import Json
from conformance.execution_profile import ExecutionProfile, measured_profile
from conformance.native_connection import Connection, library_path, load_library
from conformance.native_record import record_sql


@dataclass(frozen=True)
class PragmaCase:
    """One coverage case of pragmas: setup and SQL, the requirement identifiers it covers,
    descriptive features, and whether it runs under the profile with recursive triggers on
    ({recursive_profile}) instead of SQLite's default profile."""

    name: str
    setup: str
    sql: str
    requirements: tuple[str, ...]
    features: tuple[str, ...]
    recursive: bool = False


def definitions() -> list[PragmaCase]:
    """The coverage cases of pragmas, in the order of the outcomes of the task."""
    from conformance.authored_pragma_checks import check_definitions
    from conformance.authored_pragma_schema import schema_definitions
    return check_definitions() + schema_definitions()


def recursive_profile() -> ExecutionProfile:
    """A measured profile of format 3 with SQLite's default settings, except that recursive
    triggers are on: the profile `recursive-triggers`. The recorder turns the setting on before
    the setup and checks it after the script."""
    with TemporaryDirectory(prefix="recursive-triggers-profile-") as directory:
        connection = Connection(load_library(library_path()), Path(directory) / "measure.db")
        try:
            return measured_profile(connection, name="recursive-triggers-v1", format_version=3, recursive_triggers=True)
        finally:
            connection.close()


def records(cases: list[PragmaCase] | None = None) -> list[dict[str, Json]]:
    """Record each case natively as a version 5 record with outputs, under its profile, in the
    part `pragmas`, with its features."""
    selected = definitions() if cases is None else cases
    profiles = {False: default_profile(()), True: recursive_profile()}
    return [{**record_sql(case.setup, case.sql, name=case.name, requirements=list(case.requirements), outputs=True,
                          profile=profiles[case.recursive]),
             "part": "pragmas", "features": list(case.features)}
            for case in selected]
