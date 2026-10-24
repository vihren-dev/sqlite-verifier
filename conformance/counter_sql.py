"""The SQL that the authored cases of the connection counters share (`conformance.authored_counters`)."""

READ = " SELECT changes(), total_changes(), last_insert_rowid();"
"""The three counters, as a query."""
ROWS = "CREATE TABLE t(a INTEGER PRIMARY KEY, b TEXT UNIQUE); INSERT INTO t VALUES (1, 'a'), (2, 'b'), (3, 'c');"
"""A table with a rowid alias and a UNIQUE column, and three rows."""
PLAIN = "CREATE TABLE t(a INTEGER PRIMARY KEY, b TEXT); INSERT INTO t VALUES (1, 'a'), (2, 'b'), (3, 'c');"
"""A table with a rowid alias and no key but the rowid, and three rows."""
VALUES = "CREATE TABLE r(a INTEGER PRIMARY KEY, n, m); INSERT INTO r VALUES (1, 0, 0), (2, 0, 0), (3, 0, 0);"
"""A table with a rowid alias and two columns that the cases fill with counters, and three rows."""
LOGGED = ("CREATE TABLE t(a INTEGER PRIMARY KEY, b TEXT); CREATE TABLE log(x); "
          "CREATE TRIGGER i AFTER INSERT ON t BEGIN INSERT INTO log VALUES (new.a), (new.a); END; "
          "CREATE TRIGGER u AFTER UPDATE ON t BEGIN INSERT INTO log VALUES (old.a); END; "
          "CREATE TRIGGER d AFTER DELETE ON t BEGIN INSERT INTO log VALUES (old.a), (old.a), (old.a); END;")
"""A table whose AFTER triggers write two, one and three rows into a log."""
PARENT = ("CREATE TABLE p(id INTEGER PRIMARY KEY, k TEXT UNIQUE); "
          "CREATE TABLE c(x REFERENCES p(id) ON DELETE CASCADE ON UPDATE CASCADE, y REFERENCES p(k) ON DELETE SET NULL); "
          "INSERT INTO p VALUES (1, 'a'), (2, 'b'), (3, 'c'); "
          "INSERT INTO c VALUES (1, 'b'), (1, 'a'), (2, 'a'), (3, 'c');")
"""A parent with a rowid key and a TEXT key, and a child with a cascading and a nulling key."""
REFERENCED = ("CREATE TABLE p(id INTEGER PRIMARY KEY); CREATE TABLE c(x REFERENCES p ON DELETE CASCADE); "
              "INSERT INTO p VALUES (1), (2), (3), (4); INSERT INTO c VALUES (1), (1), (3);")
"""A parent with four rows and a child with three rows that cascade from two of them."""
CHECKED = "CREATE TABLE n(a INTEGER PRIMARY KEY, b NOT NULL, c CHECK (c > 0));"
"""A table whose rows can fail a NOT NULL or a CHECK constraint."""
BOUNDED = "CREATE TABLE k(a INTEGER PRIMARY KEY, v CHECK (v < 10)); INSERT INTO k VALUES (1, 1), (2, 2), (3, 3);"
"""A table whose rows have values below 10, so that an UPDATE that multiplies them can fail."""
RAISING = ("CREATE TABLE t(a INTEGER PRIMARY KEY); CREATE TABLE log(x); "
           "CREATE TRIGGER g BEFORE INSERT ON t BEGIN INSERT INTO log VALUES (new.a); "
           "SELECT RAISE(ABORT, 'negative') WHERE new.a < 0; END;")
"""A table whose BEFORE INSERT trigger logs each key, then fails for a negative key."""
EXITING = ("CREATE TABLE t(a INTEGER PRIMARY KEY, v); "
           "CREATE TRIGGER after_raise AFTER INSERT ON t WHEN new.v < 0 BEGIN SELECT RAISE(ABORT, 'after'); END; "
           "CREATE TRIGGER before_raise BEFORE INSERT ON t WHEN new.v < -5 BEGIN SELECT RAISE(ABORT, 'before'); END;")
"""A table whose AFTER INSERT trigger fails for a negative value, and whose BEFORE INSERT trigger fails
for a value below -5."""
CHILD = ("CREATE TABLE par(id INTEGER PRIMARY KEY); CREATE TABLE ch(a INTEGER PRIMARY KEY, pid REFERENCES par(id)); "
         "INSERT INTO par VALUES (1);")
"""A parent with the key 1 and a child that references it."""
RESTRICTED = ("CREATE TABLE p(id INTEGER PRIMARY KEY, v UNIQUE); CREATE TABLE c(x REFERENCES p(id) ON DELETE RESTRICT); "
              "INSERT INTO p VALUES (1, 1); INSERT INTO c VALUES (1);")
"""A parent with a UNIQUE column and a child whose key forbids the delete of the parent."""
