"""Neutral review boundaries supplement the historical ADR 0005 authored catalogs."""

from conformance.authored_cases import AuthoredCase


def definitions() -> list[AuthoredCase]:
    """Exercise deferred commit checks and non-NULL REAL conversion without predicting outcomes."""
    setup = "CREATE TABLE parent(id INTEGER PRIMARY KEY);" \
        "CREATE TABLE child(id INTEGER PRIMARY KEY,pid INTEGER REFERENCES parent(id) " \
        "DEFERRABLE INITIALLY DEFERRED);"
    prefix = "BEGIN IMMEDIATE; INSERT INTO child VALUES(10,1);" \
        "SELECT id,pid FROM child ORDER BY id;"
    return [
        AuthoredCase("deferred-foreign-key-repaired-commit", setup,
            prefix + "INSERT INTO parent VALUES(1); COMMIT; SELECT id,pid FROM child ORDER BY id;",
            (), ("foreign-key", "deferred-foreign-key", "transaction"), profile="foreign-keys"),
        AuthoredCase("deferred-foreign-key-commit-failure", setup,
            prefix + "COMMIT;", (),
            ("foreign-key", "deferred-foreign-key", "transaction", "constraint-failure"),
            profile="foreign-keys"),
        AuthoredCase("cast-real-numeric-prefix-arithmetic", "",
            "SELECT CAST(? AS REAL) AS as_real,CAST(? AS NUMERIC) AS as_numeric,"
            "CAST(? AS INTEGER) AS as_integer,CAST(? AS REAL)+0.25 AS arithmetic;",
            (), ("cast", "real-arithmetic", "numeric-edges", "typed-parameters"),
            (((3, b"123.5abc"), (3, b"123.5abc"), (3, b"123abc"), (3, b"123.5abc")),)),
    ]
