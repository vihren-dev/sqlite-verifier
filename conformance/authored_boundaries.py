"""Native boundaries from issues 14/18, frozen before later model development."""

from conformance.authored_cases import AuthoredCase


def default_definitions() -> list[AuthoredCase]:
    """Expose default affinity and row-dependent ADD rejection without predicting SQLite."""
    populated = "CREATE TABLE t(a INTEGER); INSERT INTO t VALUES(7);"
    empty = "CREATE TABLE t(a INTEGER);"
    cases = [
        AuthoredCase("add-default-storage-classes", populated,
            "ALTER TABLE t ADD nullable BLOB DEFAULT NULL;"
            "ALTER TABLE t ADD integer_value INTEGER DEFAULT '3.0e+5';"
            "ALTER TABLE t ADD real_value REAL DEFAULT 1;"
            "ALTER TABLE t ADD text_value TEXT DEFAULT 42;"
            "ALTER TABLE t ADD blob_value BLOB DEFAULT X'00ff';"
            "ALTER TABLE t ADD numeric_value NUMERIC DEFAULT '1.5';"
            "ALTER TABLE t ADD required TEXT NOT NULL DEFAULT 'open';"
            "ALTER TABLE t ADD parenthesized INTEGER DEFAULT (42);"
            "ALTER TABLE t ADD negative INTEGER DEFAULT -7;"
            "SELECT * FROM t; INSERT INTO t(a) VALUES(?) RETURNING *;"
            "SELECT a,typeof(nullable) AS null_type,typeof(integer_value) AS int_type,"
            "typeof(real_value) AS real_type,typeof(text_value) AS text_type,"
            "typeof(blob_value) AS blob_type,typeof(numeric_value) AS numeric_type,"
            "typeof(required) AS required_type,typeof(parenthesized) AS parent_type,"
            "typeof(negative) AS negative_type FROM t ORDER BY a;",
            ("R-07343-35026", "R-12572-62501", "R-18814-23501",
             "R-18885-42713", "R-54378-38553", "R-29868-13536"),
            ("add-column", "defaults", "default-affinity", "storage-classes", "not-null",
             "omitted-columns", "typed-parameters", "returning", "parenthesized-constant"),
            ((),) * 10 + (((1, 8),), ())),
        AuthoredCase("add-not-null-empty", empty,
            "ALTER TABLE t ADD v TEXT NOT NULL; SELECT a,v FROM t;", (),
            ("add-column", "not-null", "empty-table", "empty-result")),
        AuthoredCase("add-not-null-populated", populated,
            "ALTER TABLE t ADD v TEXT NOT NULL;", ("R-29868-13536",),
            ("add-column", "not-null", "single-row", "native-error")),
        AuthoredCase("add-not-null-null-empty", empty,
            "ALTER TABLE t ADD v TEXT NOT NULL DEFAULT NULL; SELECT a,v FROM t;", (),
            ("add-column", "not-null", "null-default", "empty-table", "empty-result")),
        AuthoredCase("add-not-null-null-populated", populated,
            "ALTER TABLE t ADD v TEXT NOT NULL DEFAULT NULL;", ("R-29868-13536",),
            ("add-column", "not-null", "null-default", "single-row", "native-error")),
        AuthoredCase("add-not-null-empty-insert", empty,
            "ALTER TABLE t ADD v TEXT NOT NULL; INSERT INTO t(a) VALUES(?);",
            ("R-31795-57643", "R-42316-09582"),
            ("add-column", "not-null", "omitted-columns", "constraint-failure", "typed-parameters"),
            ((), ((1, 8),))),
    ]
    for name, declaration, tag in [
        ("primary-key", "v INTEGER PRIMARY KEY", "R-45735-05060"),
        ("unique", "v INTEGER UNIQUE", "R-45735-05060"),
        ("stored", "v INTEGER GENERATED ALWAYS AS(a+1) STORED", "R-16727-13091"),
        ("expression", "v INTEGER DEFAULT (1+2)", "R-37287-38238"),
    ]:
        cases.append(AuthoredCase("add-rejected-" + name, populated,
            "ALTER TABLE t ADD " + declaration + ";", (tag,), ("add-column", "native-error", name)))
    cases.append(AuthoredCase("add-rejected-references",
        "CREATE TABLE parent(id INTEGER PRIMARY KEY); INSERT INTO parent VALUES(1);" + populated,
        "ALTER TABLE t ADD v INTEGER REFERENCES parent DEFAULT 1;", ("R-13876-13274",),
        ("add-column", "foreign-key", "defaults", "native-error"), profile="foreign-keys"))
    cases.append(AuthoredCase("add-rejected-current-timestamp", populated,
        "ALTER TABLE t ADD v TEXT DEFAULT CURRENT_TIMESTAMP;", ("R-37287-38238",),
        ("add-column", "defaults", "controlled-clock", "native-error"),
        profile="clock", clocks=(1700000000000,)))
    return cases


def validity_definitions() -> list[AuthoredCase]:
    """Contrast native-valid subset boundaries with genuinely invalid definitions."""
    accepted = [
        ("empty-column-name", 'CREATE TABLE t("" INTEGER); INSERT INTO t VALUES(?); SELECT "" FROM t;',
         (), ((), ((3, b"value"),), ())),
        ("rowid-shadow", "CREATE TABLE t(rowid INTEGER,oid TEXT);"
         "INSERT INTO t VALUES(?,?); SELECT rowid,oid,_rowid_ FROM t;",
         ("R-26501-17306",), ((), ((1, 9), (3, b"alias")), ())),
        ("repeated-primary-key", "CREATE TABLE t(a INTEGER,b TEXT,PRIMARY KEY(a,a));"
         "INSERT INTO t VALUES(7,'key'); SELECT a,b FROM t;", ("R-31775-48204",), None),
        ("repeated-unique-key", "CREATE TABLE t(a INTEGER,UNIQUE(a,a));"
         "INSERT INTO t VALUES(NULL),(NULL); SELECT a FROM t;", ("R-00404-17670",), None),
        ("repeated-index-column", "CREATE TABLE t(a INTEGER); CREATE INDEX i ON t(a,a);"
         "INSERT INTO t VALUES(7); SELECT a FROM t;", (), None),
        ("identifier-case", 'CREATE TABLE "Foo"("Bar" INTEGER);'
         'INSERT INTO foo(bar) VALUES(7); SELECT "Bar" FROM "Foo";', (), None),
        ("integer-primary-key-sequence", "CREATE TABLE t(id INTEGER PRIMARY KEY AUTOINCREMENT,v TEXT);"
         "INSERT INTO t(v) VALUES('value'); SELECT id,v FROM t; SELECT name,seq FROM sqlite_sequence;",
         ("R-07986-46024", "R-47901-33947"), None),
    ]
    cases = [AuthoredCase("validity-" + name, "", sql, tags,
        ("native-valid", "model-boundary", name), parameters) for name, sql, tags, parameters in accepted]
    for name, sql, tags in [
        ("no-columns", "CREATE TABLE t();", ()),
        ("duplicate-column", "CREATE TABLE t(a INTEGER,A TEXT);", ()),
        ("missing-key-column", "CREATE TABLE t(a INTEGER,PRIMARY KEY(b));", ()),
        ("reserved-name", "CREATE TABLE sqlite_x(a INTEGER);", ("R-17899-04554",)),
    ]:
        cases.append(AuthoredCase("validity-" + name, "", sql, tags,
            ("native-error", "invalid-definition", name)))
    return cases


def definitions() -> list[AuthoredCase]:
    """Select the additional C6 cases without changing the retained C5 catalog."""
    return default_definitions() + validity_definitions()
