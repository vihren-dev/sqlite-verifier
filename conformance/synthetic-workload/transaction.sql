BEGIN IMMEDIATE;
INSERT INTO parent VALUES(?, ?) RETURNING id, label;
INSERT INTO child VALUES(?, ?), (?, ?);
SELECT id, label FROM parent ORDER BY id;
DELETE FROM parent WHERE id = ? RETURNING id;
SELECT id FROM child ORDER BY id;
SELECT parent_id FROM audit ORDER BY parent_id;
COMMIT;
