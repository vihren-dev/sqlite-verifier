"""SQL inputs of the parser tests, shared with the checks of the parser library.

`tests/parser_test.py` parses them with the executables. The parser library checks parse
the same inputs with each grammar of the library, and compare the results.
"""

VALID = (
    ('empty', b''),
    ('line_comment', b'-- only a comment'),
    ('comment_semicolons', b'/* comment */ ; ;'),
    ('create_add', b'CREATE TABLE t(a TEXT); ALTER TABLE t ADD COLUMN b INTEGER;'),
    ('quoted_names', b"CREATE TABLE 'quoted name'([x;y] TEXT, `z``a` BLOB);"),
    ('trigger_semicolons', b"CREATE TRIGGER tr AFTER INSERT ON missing BEGIN SELECT 'a;b'; SELECT 2; END; SELECT 3;"),
    ('literal_tokens', b"SELECT ';', 'it''s', X'00FF', 1_000, ?1, :named; -- end"),
    ('contextual_keywords', b'CREATE TABLE window(over, filter, key); SELECT over, filter FROM window;'),
    ('window_filter', b'SELECT sum(x) FILTER (WHERE x>0) OVER (PARTITION BY a ORDER BY b) FROM absent;'),
    ('named_window', b'SELECT sum(x) OVER win FROM absent WINDOW win AS (ORDER BY x);'),
    ('recursive_cte', b'WITH RECURSIVE c(x) AS (VALUES(1) UNION ALL SELECT x+1 FROM c WHERE x<3) SELECT * FROM c;'),
    ('upsert_returning', b'INSERT INTO absent(a) VALUES(1) ON CONFLICT(a) DO UPDATE SET a=excluded.a RETURNING a;'),
    ('virtual_table', b"CREATE VIRTUAL TABLE absent USING uninstalled(a, tokenize='porter unicode61');"),
    ('strict_generated', b"CREATE TABLE s(id INTEGER PRIMARY KEY, x TEXT GENERATED ALWAYS AS ('x')) STRICT;"),
    ('expression_index', b'CREATE INDEX i ON absent((x+1)) WHERE x IS NOT NULL;'),
    ('attach_pragma_vacuum', b"ATTACH ':memory:' AS aux; DETACH aux; PRAGMA main.user_version=1; VACUUM;"),
    ('transaction_savepoint', b'BEGIN IMMEDIATE; SAVEPOINT s; ROLLBACK TO s; RELEASE s; COMMIT;'),
    ('explain_delete', b'EXPLAIN QUERY PLAN SELECT * FROM missing; DELETE FROM missing RETURNING *;'),
    ('update_analyze_reindex', b'UPDATE missing SET a=1 WHERE a=0 RETURNING a; ANALYZE missing; REINDEX;'),
    ('deep_nesting', b'SELECT ' + b'(' * 5000 + b'1' + b')' * 5000 + b';'),
    ('unicode_bom', b'\xef\xbb\xbfCREATE TABLE "caf\xc3\xa9"("\xd0\xbd\xd0\xb0\xd0\xbc\xd0\xb5" TEXT); /*\xe7\xb5\x82*/ ALTER TABLE "caf\xc3\xa9" ADD "\xf0\x9f\x92\xa1";'),
)
"""Scripts that both pinned grammars accept, one for each grammar family."""
INVALID = (
    ('incomplete_select', b'SELECT'),
    ('incomplete_create', b'CREATE TABLE t('),
    ('unterminated_string', b"SELECT 'unterminated"),
    ('odd_blob', b"SELECT X'odd'"),
    ('trailing_nonsense', b'CREATE TABLE t(a); nonsense;'),
    ('embedded_nul', b'SELECT 1\x00; DROP TABLE t;'),
    ('invalid_utf8', b"SELECT '\xff';"),
    ('incomplete_trigger', b'CREATE TRIGGER t AFTER INSERT ON x BEGIN SELECT 1;'),
    ('update_limit', b'UPDATE t SET a=1 LIMIT 1'),
    ('invalid_variable', b'SELECT @;'),
    ('utf8_surrogate', b"SELECT '\xed\xa0\x80';"),
    ('double_separator', b'SELECT 1__2'),
    ('trailing_separator', b'SELECT 1_'),
    ('hex_double_separator', b'SELECT 0xA__B'),
    ('separator_before_decimal', b'SELECT 1_.2'),
)
"""Bytes or scripts that both pinned grammars reject with INPUT_ERROR."""

OVERSIZED = b" " * (1024 * 1024 + 1)
"""One byte more than the parser's input limit: the result is RESOURCE_LIMIT."""
RAISE_EXPRESSION = b"CREATE TRIGGER tr BEFORE INSERT ON t BEGIN SELECT RAISE(FAIL, 1+2); END;"
"""An expression in RAISE: SQLite 3.47 added it, so 3.51.0 accepts it and 3.46.0 rejects it."""
UNICODE_SPANS = 'CREATE TABLE "café"("💡" TEXT);'.encode()
"""Quoted names with multi-byte characters, for exact byte spans."""


def all_inputs() -> list[bytes]:
    """Return every input of the parser tests once, in a fixed order."""
    inputs = [sql for _, sql in VALID + INVALID] + [OVERSIZED, RAISE_EXPRESSION, UNICODE_SPANS]
    return list(dict.fromkeys(inputs))
