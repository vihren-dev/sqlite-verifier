"""Bounded end-to-end checks of grammar recognition and source-bound syntax trees."""

import json
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def parse(sql: bytes, expected: str = "PARSED") -> dict[str, object]:
    """Exercise the executable interface, checking every parse against its exit code."""
    with tempfile.TemporaryDirectory() as directory:
        path = Path(directory) / "input.sql"
        path.write_bytes(sql)
        result = subprocess.run([str(ROOT / "build/sqlite-parser"), str(path)],
                                capture_output=True, text=True, timeout=3)
    value: dict[str, object] = json.loads(result.stdout)
    assert value["status"] == expected, (sql, result.returncode, value, result.stderr)
    assert result.returncode == (0 if expected == "PARSED" else 1), result
    if expected == "PARSED":
        nodes = value["nodes"]
        assert isinstance(nodes, list)
        for node in nodes:
            assert 0 <= node["start"] <= node["end"] <= len(sql), node
            assert all(0 <= child < len(nodes) for child in node["children"])
        assert nodes[value["root"]]["symbol"] == "input"
    return value


def main() -> None:
    """Cover full grammar families, lexical boundaries, and rejection without schema lookup."""
    valid = [
        "", "-- only a comment", "/* comment */ ; ;",
        "CREATE TABLE t(a TEXT); ALTER TABLE t ADD COLUMN b INTEGER;",
        "CREATE TABLE 'quoted name'([x;y] TEXT, `z``a` BLOB);",
        "CREATE TRIGGER tr AFTER INSERT ON missing BEGIN SELECT 'a;b'; SELECT 2; END; SELECT 3;",
        "SELECT ';', 'it''s', X'00FF', 1_000, ?1, :named; -- end",
        "CREATE TABLE window(over, filter, key); SELECT over, filter FROM window;",
        "SELECT sum(x) FILTER (WHERE x>0) OVER (PARTITION BY a ORDER BY b) FROM absent;",
        "SELECT sum(x) OVER win FROM absent WINDOW win AS (ORDER BY x);",
        "WITH RECURSIVE c(x) AS (VALUES(1) UNION ALL SELECT x+1 FROM c WHERE x<3) SELECT * FROM c;",
        "INSERT INTO absent(a) VALUES(1) ON CONFLICT(a) DO UPDATE SET a=excluded.a RETURNING a;",
        "CREATE VIRTUAL TABLE absent USING uninstalled(a, tokenize='porter unicode61');",
        "CREATE TABLE s(id INTEGER PRIMARY KEY, x TEXT GENERATED ALWAYS AS ('x')) STRICT;",
        "CREATE INDEX i ON absent((x+1)) WHERE x IS NOT NULL;",
        "ATTACH ':memory:' AS aux; DETACH aux; PRAGMA main.user_version=1; VACUUM;",
        "BEGIN IMMEDIATE; SAVEPOINT s; ROLLBACK TO s; RELEASE s; COMMIT;",
        "EXPLAIN QUERY PLAN SELECT * FROM missing; DELETE FROM missing RETURNING *;",
        "UPDATE missing SET a=1 WHERE a=0 RETURNING a; ANALYZE missing; REINDEX;",
        '\ufeffCREATE TABLE "café"("наме" TEXT); /*終*/ ALTER TABLE "café" ADD "💡";',
    ]
    for sql in valid:
        parse(sql.encode())
    for sql in [b"SELECT", b"CREATE TABLE t(", b"SELECT 'unterminated",
                b"SELECT X'odd'", b"CREATE TABLE t(a); nonsense;",
                b"SELECT 1\x00; DROP TABLE t;", b"SELECT '\xff';",
                b"CREATE TRIGGER t AFTER INSERT ON x BEGIN SELECT 1;",
                b"UPDATE t SET a=1 LIMIT 1", b"SELECT @;", b"SELECT '\xed\xa0\x80';",
                b"SELECT 1__2", b"SELECT 1_", b"SELECT 0xA__B", b"SELECT 1_.2"]:
        parse(sql, "INPUT_ERROR")
    parse(b" " * (1024 * 1024 + 1), "RESOURCE_LIMIT")
    text = 'CREATE TABLE "café"("💡" TEXT);'.encode()
    result = parse(text)
    assert result == parse(text), "CST output is nondeterministic"
    nodes = result["nodes"]
    assert isinstance(nodes, list)
    quoted = [text[node["start"]:node["end"]] for node in nodes if node["symbol"] == "ID"]
    assert '"café"'.encode() in quoted and '"💡"'.encode() in quoted, quoted
    print(f"parser checks passed: {len(valid)} grammar scripts, malformed/limit and byte-span cases")


if __name__ == "__main__":
    main()
