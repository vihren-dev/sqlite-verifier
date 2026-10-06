"""Authored native evidence for requirement areas the public Tcl pilot does not cover."""

from conformance.case_format import Json
from conformance.native_record import record_sql


def definitions() -> list[tuple[str, str, str, list[str]]]:
    """Expose unchanged SQL scenarios so new corpora can acquire richer native evidence."""
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
    definitions += [
        ("numeric-text-integer", "CREATE TABLE t(v NUMERIC);", "INSERT INTO t VALUES(' 1');",
         ["R-12079-51392", "R-64016-22984"]),
        ("numeric-exponent", "CREATE TABLE t(v NUMERIC);", "INSERT INTO t VALUES('3.0e+5');",
         ["R-05192-57965", "R-36476-47203"]),
        ("numeric-real-to-integer", "CREATE TABLE t(v NUMERIC);", "INSERT INTO t VALUES(1.0);",
         ["R-22849-20349"]),
        ("text-numeric-conversion", "CREATE TABLE t(v TEXT);", "INSERT INTO t VALUES(42);",
         ["R-54378-38553", "R-21926-12440"]),
        ("real-integer-conversion", "CREATE TABLE t(v REAL);", "INSERT INTO t VALUES(42);",
         ["R-18885-42713"]),
        ("integer-numeric-equivalence", "CREATE TABLE t(i INTEGER,n NUMERIC);", "INSERT INTO t VALUES('1.0','1.0');",
         ["R-15334-58407"]),
        ("charint-priority", "CREATE TABLE t(v CHARINT);", "INSERT INTO t VALUES('42');",
         ["R-23153-04437", "R-14349-34154", "R-07051-38416"]),
        ("varchar-affinity", "CREATE TABLE t(v VARCHAR(20));", "INSERT INTO t VALUES(42);",
         ["R-42648-01192", "R-00243-07929"]),
        ("floating-point-affinity", 'CREATE TABLE t(v "FLOATING POINT");', "INSERT INTO t VALUES('42');",
         ["R-38971-13593"]),
        ("untyped-storage", "CREATE TABLE t(v);", "INSERT INTO t VALUES('1'); INSERT INTO t VALUES(1);",
         ["R-63063-00748"]),
        ("string-is-numeric", "CREATE TABLE t(v STRING);", "INSERT INTO t VALUES('42');",
         ["R-30879-62015", "R-41025-56247"]),
        ("commit-end-alias", "CREATE TABLE t(v BLOB);", "BEGIN; INSERT INTO t(v) VALUES(1); END TRANSACTION;",
         ["R-11129-23371", "R-29897-28851"]),
        ("implicit-write-commit", "CREATE TABLE t(v BLOB);", "INSERT INTO t(v) VALUES(1);",
         ["R-55258-32329", "R-62157-11346"]),
        ("savepoint-rollback", "CREATE TABLE t(v BLOB);", "SAVEPOINT s; INSERT INTO t VALUES(1); ROLLBACK;",
         ["R-50442-34254", "R-58433-37187"]),
        ("begin-immediate", "CREATE TABLE t(v BLOB);", "BEGIN IMMEDIATE; INSERT INTO t VALUES(1); COMMIT;",
         ["R-04905-56085", "R-43433-49136"]),
        ("begin-default-deferred", "CREATE TABLE t(v BLOB);", "BEGIN; COMMIT;",
         ["R-52668-48601"]),
        ("create-ordinary-index", "CREATE TABLE t(v INTEGER); INSERT INTO t VALUES(1);", "CREATE INDEX i ON t(v);",
         ["R-57025-62168", "R-09773-40602"]),
        ("create-unique-duplicate", "CREATE TABLE t(v INTEGER); INSERT INTO t VALUES(1),(1);", "CREATE UNIQUE INDEX i ON t(v);",
         ["R-06718-34797"]),
        ("index-if-not-exists", "CREATE TABLE t(v INTEGER); CREATE INDEX i ON t(v);", "CREATE INDEX IF NOT EXISTS i ON t(v);",
         ["R-16085-53730"]),
        ("drop-index", "CREATE TABLE t(v INTEGER); CREATE INDEX i ON t(v);", "DROP INDEX i;", ["R-25613-37547"]),
        ("index-subquery", "CREATE TABLE t(v INTEGER);", "CREATE INDEX i ON t((SELECT v FROM t));",
         ["R-11135-63542"]),
        ("index-descending", "CREATE TABLE t(v INTEGER); INSERT INTO t VALUES(1),(2);", "CREATE INDEX i ON t(v DESC);",
         ["R-32925-06786"]),
        ("index-collation", "CREATE TABLE t(v TEXT);", "CREATE INDEX i ON t(v COLLATE NOCASE);",
         ["R-48616-47814"]),
    ]
    return definitions


def records() -> list[dict[str, Json]]:
    """Preserve legacy recording; each tag denotes only its named scenario."""
    return [record_sql(setup, sql, name=name, requirements=tags)
            for name, setup, sql, tags in definitions()]
