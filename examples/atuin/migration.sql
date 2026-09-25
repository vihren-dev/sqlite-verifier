BEGIN;
alter table history add column shell text;
INSERT INTO _sqlx_migrations
    (version, description, installed_on, success, checksum, execution_time)
VALUES
    (20260709214605, 'shell', '2026-09-25 00:00:00', 1,
     X'5376BB3DDC6A9956652BFF2B9807B64A83219A4201D1F1E7DE9F7760F2507F191856AE5F549A7613253D1284C9A1B988', -1);
COMMIT;
UPDATE _sqlx_migrations
SET execution_time = 1000000
WHERE version = 20260709214605;
