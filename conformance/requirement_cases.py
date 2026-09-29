"""Authored native evidence for requirement areas the public Tcl pilot does not cover."""

from conformance.case_format import Json
from conformance.native_record import record_sql


def records() -> list[dict[str, Json]]:
    """Each tag denotes the named scenario only, never complete requirement coverage."""
    definitions = [
        ("blob-affinity", "CREATE TABLE t(v BLOB);",
         "INSERT INTO t(v) VALUES(1); INSERT INTO t(v) VALUES('1'); INSERT INTO t(v) VALUES(X'00'); INSERT INTO t(v) VALUES(NULL);",
         ["R-03366-15091"]),
        ("explicit-rollback", "CREATE TABLE t(v BLOB);", "BEGIN; INSERT INTO t(v) VALUES(X'00'); ROLLBACK;",
         ["R-36570-50350", "R-29897-28851"]),
        ("nested-begin", "CREATE TABLE t(v BLOB);", "BEGIN; BEGIN;", ["R-11576-11990"]),
        ("index-duplicate", "CREATE TABLE t(id INTEGER); CREATE UNIQUE INDEX ux ON t(id); INSERT INTO t VALUES(1);",
         "INSERT INTO t(id) VALUES(1);", ["R-17379-32951", "R-06718-34797"]),
        ("index-null", "CREATE TABLE t(id INTEGER); CREATE UNIQUE INDEX ux ON t(id);",
         "INSERT INTO t(id) VALUES(NULL); INSERT INTO t(id) VALUES(NULL);", ["R-55137-26834"]),
        ("add-null-populated", "CREATE TABLE t(id INTEGER); INSERT INTO t(rowid,id) VALUES(-4,7),(9,NULL);",
         "ALTER TABLE t ADD note TEXT;", ["R-10948-48115", "R-42316-09582"]),
    ]
    return [record_sql(setup, sql, name=name, requirements=tags) for name, setup, sql, tags in definitions]
