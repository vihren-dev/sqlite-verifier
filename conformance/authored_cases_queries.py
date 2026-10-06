"""Neutral query and clock inputs for ADR 0005 C5 result boundaries."""

from conformance.authored_cases import AuthoredCase


def query_definitions() -> list[AuthoredCase]:
    """Retain projected sort keys so native boundary probes can observe full tie groups."""
    aggregate = "SELECT count(*) AS rows,count(v) AS nonnull,sum(v) AS sum,avg(v) AS avg,max(v) AS max FROM t;"
    return [
        AuthoredCase("aggregates-empty-single-null-groups", "CREATE TABLE t(k,v);",
            aggregate + "INSERT INTO t VALUES('one',2);" + aggregate +
            "INSERT INTO t VALUES(NULL,NULL),(NULL,4),('one',NULL),('',1);" + aggregate +
            "SELECT k,count(*) AS rows,count(v) AS nonnull,sum(v) AS sum,avg(v) AS avg,max(v) AS max "
            "FROM t GROUP BY k ORDER BY k;",
            ("R-13776-21310", "R-34280-42283", "R-17177-10067", "R-44223-43966",
             "R-50775-16353", "R-02223-49279", "R-14926-50129"),
            ("count", "sum", "avg", "max", "group-by", "empty-table", "single-row", "null", "empty-values")),
        AuthoredCase("join-coalesce-cast-real",
            "CREATE TABLE left_side(id INTEGER,v); CREATE TABLE right_side(id INTEGER,v);"
            "INSERT INTO left_side VALUES(1,NULL),(2,''); INSERT INTO right_side VALUES(1,'match');",
            "SELECT l.id AS id,l.v AS left_value,r.v AS right_value "
            "FROM left_side AS l JOIN right_side AS r ON l.id=r.id ORDER BY id;"
            "SELECT l.id AS id,l.v AS left_value,r.v AS right_value,coalesce(l.v,r.v) AS chosen "
            "FROM left_side AS l LEFT JOIN right_side AS r ON l.id=r.id ORDER BY id;"
            "SELECT coalesce(NULL,NULL) AS absent,coalesce(NULL,'',5) AS empty,"
            "CAST(-1.9 AS INTEGER) AS truncated,CAST(NULL AS REAL) AS null_cast,'1.5'+2 AS arithmetic;",
            ("R-38465-03616", "R-24610-05866", "R-22655-13879", "R-02752-50091",
             "R-32434-09092", "R-12720-41494"),
            ("join", "left-join", "coalesce", "cast", "real-arithmetic", "null", "empty-values")),
        AuthoredCase("numeric-ties-windows",
            "CREATE TABLE t(k,v); INSERT INTO t VALUES"
            "(NULL,'null'),(1,'integer'),(1.0,'real'),(1,'integer-again'),(2,'middle'),(3,'a'),(3,'b');",
            "SELECT k,v FROM t ORDER BY k; SELECT k,v FROM t ORDER BY k LIMIT ? OFFSET ?;"
            "SELECT k,v FROM t ORDER BY k LIMIT ? OFFSET ?; SELECT k,v FROM t LIMIT ? OFFSET ?;"
            "SELECT k,v FROM t ORDER BY k LIMIT 0;",
            ("R-12881-55998", "R-21555-60916", "R-20467-43422", "R-33750-29536"),
            ("order-by", "limit", "offset", "numeric-ties", "two-boundary-groups",
             "shared-boundary-group", "unordered-window", "null", "empty-result", "typed-parameters"),
            ((), ((1, 4), (1, 2)), ((1, 1), (1, 2)), ((1, 2), (1, 2)), ())),
        AuthoredCase("ordered-distinct-nocase",
            "CREATE TABLE t(x TEXT COLLATE NOCASE); INSERT INTO t VALUES('a'),('A'),('b'),('b');",
            "SELECT DISTINCT x COLLATE BINARY AS x FROM t ORDER BY x COLLATE NOCASE DESC;"
            "SELECT DISTINCT x COLLATE BINARY AS x FROM t ORDER BY x COLLATE NOCASE DESC LIMIT 2;",
            ("R-14442-41305", "R-64199-22471"), ("distinct", "nocase-ties", "order-by", "limit")),
        AuthoredCase("clock-format-default-trigger",
            "CREATE TABLE t(stamp TEXT DEFAULT CURRENT_TIMESTAMP,epoch INTEGER DEFAULT(unixepoch()));"
            "CREATE TABLE audit(stamp,epoch); CREATE TRIGGER log AFTER INSERT ON t BEGIN "
            "INSERT INTO audit VALUES(CURRENT_TIMESTAMP,unixepoch()); END;",
            "BEGIN IMMEDIATE; INSERT INTO t DEFAULT VALUES RETURNING stamp,epoch;"
            "SELECT stamp,epoch,unixepoch('now') AS now,unixepoch('now') AS again,"
            "strftime('%Y-%m-%d %H:%M:%S','now') AS formatted FROM audit ORDER BY now LIMIT 1; COMMIT;",
            ("R-34818-13664", "R-48198-01058", "R-15363-55230", "R-63811-08743", "R-30877-63179"),
            ("controlled-clock", "current-timestamp", "unixepoch", "strftime", "defaults", "triggers", "transaction"),
            profile="clock", clocks=(1700000000000, 1700000001000, 1700000002000, 1700000003000)),
        AuthoredCase("json-values-empty", "",
            "SELECT json_extract(?,'$.nested.value') AS nested,json_extract(?,'$.missing') AS missing,"
            "json_extract(?,'$.null') AS explicit_null;"
            "SELECT key,value,type FROM json_each(?) ORDER BY key;"
            "SELECT key,value,type FROM json_each(?) ORDER BY key;", (),
            ("json_extract", "json_each", "typed-parameters", "null", "empty-array", "empty-result"),
            (((3, b'{"nested":{"value":7},"null":null}'),) * 3,
             ((3, b'[null,0,"",1.5]'),), ((3, b'[]'),))),
    ]
