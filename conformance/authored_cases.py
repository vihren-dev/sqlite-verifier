"""Neutral ADR 0005 C5 inputs; native acquisition remains the sole source of outcomes."""

from dataclasses import dataclass
from pathlib import Path
from tempfile import TemporaryDirectory
from typing import Literal

from conformance.case_format import Json
from conformance.execution_profile import ExecutionProfile, measured_profile
from conformance.native_connection import Cell, Connection, library_path, load_library
from conformance.native_record import record_sql
from conformance.requirement_cases import definitions as requirement_definitions


@dataclass(frozen=True)
class AuthoredCase:
    """A bounded SQL scenario with explicit acquisition inputs and scenario-level tags."""

    name: str
    setup: str
    sql: str
    requirements: tuple[str, ...]
    features: tuple[str, ...]
    parameters: tuple[tuple[Cell, ...], ...] | None = None
    profile: Literal["deferred", "immediate", "foreign-keys", "clock"] = "deferred"
    clocks: tuple[int, ...] | None = None
    part: Literal["boundary-interaction", "requirement"] = "boundary-interaction"


def write_definitions() -> list[AuthoredCase]:
    """Exercise schema and write interactions without application-specific SQL or names."""
    return [
        AuthoredCase("typed-values-edges", "CREATE TABLE t(v BLOB);",
            "INSERT INTO t VALUES(?),(?),(?),(?),(?),(?),(?),(?) RETURNING v;"
            "SELECT rowid,v,typeof(v) AS kind FROM t ORDER BY rowid;",
            ("R-03366-15091", "R-30470-29835", "R-62084-05956"),
            ("typed-parameters", "storage-classes", "integer-edges", "null", "empty-values"),
            (((5, None), (1, -(2**63)), (1, 2**63 - 1), (2, 0x3FF8000000000000),
              (3, b""), (3, b"caf\xc3\xa9\x00"), (4, b""), (4, b"\x00\xff")), ())),
        AuthoredCase("schema-defaults-add",
            "CREATE TABLE t(id TEXT PRIMARY KEY,label TEXT DEFAULT 'new',optional BLOB);",
            "INSERT INTO t(id) VALUES(?) RETURNING id,label,optional;"
            "CREATE INDEX by_label ON t(label); ALTER TABLE t ADD added TEXT DEFAULT '';"
            "SELECT id,label,optional,added FROM t ORDER BY id;",
            ("R-10948-48115", "R-18814-23501", "R-42316-09582", "R-57025-62168"),
            ("text-primary-key", "defaults", "indexes", "add-column", "single-row"),
            (((3, b"key"),), (), (), ())),
        AuthoredCase("transaction-trigger-cascade-counts",
            "CREATE TABLE parent(id INTEGER PRIMARY KEY);"
            "CREATE TABLE child(id INTEGER PRIMARY KEY,pid REFERENCES parent ON DELETE CASCADE);"
            "CREATE TABLE audit(x); CREATE TRIGGER log AFTER INSERT ON parent BEGIN "
            "INSERT INTO audit VALUES(new.id); INSERT INTO audit VALUES(new.id); END;",
            "BEGIN IMMEDIATE; INSERT INTO parent VALUES(?),(?) RETURNING id;"
            "INSERT INTO child VALUES(10,2),(11,2); UPDATE parent SET id=id WHERE id=2;"
            "SELECT id AS missing FROM parent WHERE 0; UPDATE parent SET id=id WHERE id=99;"
            "DELETE FROM parent WHERE id=2 RETURNING id; SELECT x FROM audit ORDER BY x;"
            "COMMIT; SELECT id FROM parent ORDER BY id;",
            ("R-53938-27527", "R-33632-01248", "R-61809-62207", "R-32235-53300",
             "R-45416-45177", "R-13116-43655"),
            ("transaction", "triggers", "foreign-key-cascade", "returning", "direct-counts", "empty-result"),
            ((), ((1, 2), (1, 3)), (), (), (), (), (), (), (), ()), profile="foreign-keys"),
        AuthoredCase("upsert-returning", "CREATE TABLE t(id TEXT PRIMARY KEY,v INTEGER);",
            "INSERT INTO t VALUES(?,?) ON CONFLICT(id) DO UPDATE SET v=excluded.v RETURNING id,v;"
            "INSERT INTO t VALUES(?,?) ON CONFLICT(id) DO UPDATE SET v=excluded.v RETURNING id,v;"
            "INSERT INTO t VALUES(?,?) ON CONFLICT(id) DO NOTHING RETURNING id,v;",
            ("R-15195-28467", "R-45416-45177"), ("on-conflict", "returning", "empty-result"),
            (((3, b"a"), (1, 1)), ((3, b"a"), (1, 2)), ((3, b"a"), (1, 3)))),
        AuthoredCase("check-abort", "CREATE TABLE t(id INTEGER PRIMARY KEY,v CHECK(v>0));",
            "BEGIN; INSERT INTO t VALUES(1,NULL); INSERT INTO t VALUES(2,1),(3,0);",
            ("R-55435-14303", "R-34109-39108", "R-47224-48532"),
            ("check", "constraint-failure", "statement-rollback", "transaction", "null")),
        AuthoredCase("text-primary-key-failure",
            "CREATE TABLE t(id TEXT PRIMARY KEY); INSERT INTO t VALUES('a');",
            "INSERT INTO t VALUES('a');", ("R-06471-16287",),
            ("text-primary-key", "constraint-failure")),
        AuthoredCase("not-null-failure", "CREATE TABLE t(v TEXT NOT NULL);",
            "INSERT INTO t VALUES(?);", ("R-31795-57643",),
            ("not-null", "constraint-failure", "typed-parameters", "null"), (((5, None),),)),
        AuthoredCase("foreign-key-failure",
            "CREATE TABLE parent(id INTEGER PRIMARY KEY); CREATE TABLE child(pid REFERENCES parent);",
            "INSERT INTO child VALUES(9);", ("R-61362-32087",),
            ("foreign-key", "constraint-failure"), profile="foreign-keys"),
    ]


def definitions() -> list[AuthoredCase]:
    """Expose all 43 inputs separately from acquisition for catalog and digest checks."""
    from conformance.authored_cases_queries import query_definitions
    legacy = [AuthoredCase(name, setup, sql, tuple(tags), ("requirement-scenario",),
        profile="immediate" if name == "begin-immediate" else "deferred", part="requirement")
        for name, setup, sql, tags in requirement_definitions()]
    return write_definitions() + query_definitions() + legacy


def profiles() -> dict[str, ExecutionProfile]:
    """Measure the pinned running engine once; establish each declared profile at recording."""
    with TemporaryDirectory(prefix="authored-profile-") as directory:
        connection = Connection(load_library(library_path()), Path(directory) / "measure.db")
        try:
            return {
                "deferred": measured_profile(connection, name="authored-deferred-v1"),
                "immediate": measured_profile(connection, name="authored-immediate-v1", transaction_mode="immediate"),
                "foreign-keys": measured_profile(connection, name="authored-foreign-keys-v1",
                    foreign_keys=True, transaction_mode="immediate"),
                "clock": measured_profile(connection, name="authored-clock-v1",
                    foreign_keys=True, transaction_mode="immediate", clock="unix-milliseconds-v1"),
            }
        finally:
            connection.close()


def records() -> list[dict[str, Json]]:
    """Acquire fresh typed outputs and profiles without changing legacy corpus recording."""
    measured = profiles()
    result: list[dict[str, Json]] = []
    for case in definitions():
        record = record_sql(case.setup, case.sql, name=case.name,
            requirements=list(case.requirements), outputs=True,
            parameters=list(case.parameters) if case.parameters is not None else None,
            profile=measured[case.profile], setup_clock=1699999999000 if case.clocks else None,
            clock_values=list(case.clocks) if case.clocks else None)
        result.append({**record, "part": case.part, "features": list(case.features)})
    return result
