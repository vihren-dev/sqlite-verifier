//! Capture the pinned real SQLx migrator with Atuin's logical connection profile.
pub mod faults;
use serde_json::{Value, json};
use sqlx::sqlite::{SqliteConnectOptions, SqliteJournalMode, SqlitePoolOptions, SqliteSynchronous};
use sqlx::{AssertSqlSafe, Connection, Row, SqliteConnection, SqlitePool};
use std::{path::Path, time::Duration};

/// Export every schema object, including implicit indexes and SQLx bookkeeping.
pub async fn snapshot(conn: &mut SqliteConnection) -> Result<Value, sqlx::Error> {
    let rows = sqlx::query("SELECT type,name,tbl_name,rootpage,sql FROM sqlite_schema ORDER BY type,name")
        .fetch_all(&mut *conn).await?;
    let schema: Vec<Value> = rows.iter().map(|row| json!({
        "type": row.get::<String,_>(0), "name": row.get::<String,_>(1),
        "table": row.get::<String,_>(2), "rootpage": row.get::<i64,_>(3),
        "sql": row.get::<Option<String>,_>(4)
    })).collect();
    let rows = sqlx::query("SELECT rowid,version,description,installed_on,success,hex(checksum),execution_time FROM _sqlx_migrations ORDER BY version")
        .fetch_all(&mut *conn).await?;
    let metadata: Vec<Value> = rows.iter().map(|row| json!({
        "rowid":row.get::<i64,_>(0),
        "version": row.get::<i64,_>(1), "description": row.get::<String,_>(2),
        "installed_on": row.get::<String,_>(3), "success": row.get::<i64,_>(4),
        "checksum_hex": row.get::<String,_>(5), "execution_time": row.get::<i64,_>(6)
    })).collect();
    let mut statistics = serde_json::Map::new();
    for (table, columns) in [("sqlite_stat1",vec!["tbl","idx","stat"]),
        ("sqlite_stat4",vec!["tbl","idx","neq","nlt","ndlt","sample"])] {
        if !schema.iter().any(|row| row["name"]==table) { continue; }
        let expressions: Vec<String> = columns.iter().map(|column|
            format!("typeof({column}),quote({column}),hex(CAST({column} AS BLOB))")).collect();
        let sql = format!("SELECT rowid,{} FROM {table} ORDER BY rowid",expressions.join(","));
        let rows = sqlx::query(AssertSqlSafe(sql)).fetch_all(&mut *conn).await?;
        let values: Vec<Value> = rows.iter().map(|row| {
            let mut fields = vec![json!(row.get::<i64,_>(0))];
            for index in 1..(1+columns.len()*3) { fields.push(json!(row.get::<String,_>(index))); }
            json!(fields)
        }).collect();
        statistics.insert(table.to_owned(),json!(values));
    }
    Ok(json!({"schema":schema,"metadata":metadata,"statistics":statistics}))
}

/// Record the actual linked engine and effective connection PRAGMAs.
pub async fn profile(conn: &mut SqliteConnection) -> Result<Value, sqlx::Error> {
    let row = sqlx::query("SELECT sqlite_version(),sqlite_source_id()")
        .fetch_one(&mut *conn).await?;
    let options: Vec<String> = sqlx::query_scalar("PRAGMA compile_options")
        .fetch_all(&mut *conn).await?;
    let compiler: Vec<&String> = options.iter().filter(|flag| flag.starts_with("COMPILER=")).collect();
    let mut pragmas = serde_json::Map::new();
    for name in ["foreign_keys", "synchronous", "journal_size_limit", "busy_timeout",
        "trusted_schema", "recursive_triggers", "legacy_alter_table", "writable_schema",
        "ignore_check_constraints", "page_size", "wal_autocheckpoint"] {
        let value: i64 = sqlx::query_scalar(AssertSqlSafe(format!("PRAGMA {name}")))
            .fetch_one(&mut *conn).await?;
        pragmas.insert(name.to_owned(),json!(value));
    }
    let journal: String = sqlx::query_scalar("PRAGMA journal_mode")
        .fetch_one(&mut *conn).await?;
    pragmas.insert("journal_mode".to_owned(),json!(journal));
    let mut handle = conn.lock_handle().await?;
    let mut limits = serde_json::Map::new();
    for (name, category) in [("column",libsqlite3_sys::SQLITE_LIMIT_COLUMN),
        ("length",libsqlite3_sys::SQLITE_LIMIT_LENGTH),
        ("sql_length",libsqlite3_sys::SQLITE_LIMIT_SQL_LENGTH),
        ("expression_depth",libsqlite3_sys::SQLITE_LIMIT_EXPR_DEPTH)] {
        // The SQLx guard excludes its worker; -1 queries without changing limits.
        let value = unsafe { libsqlite3_sys::sqlite3_limit(handle.as_raw_handle().as_ptr(),category,-1) };
        limits.insert(name.to_owned(),json!(value));
    }
    Ok(json!({"sqlite_version":row.get::<String,_>(0),
        "sqlite_source_id":row.get::<String,_>(1),"compile_options":options,"pragmas":pragmas,
        "runtime_limits":limits,"compiler_identity":compiler}))
}

/// Observe any optimize-on-close changes using a read-only connection without optimization.
pub async fn closed_snapshot(path: &Path) -> Result<Value, sqlx::Error> {
    let options = SqliteConnectOptions::new().filename(path).read_only(true);
    let mut conn = SqliteConnection::connect_with(&options).await?;
    let state = snapshot(&mut conn).await?;
    conn.close().await?;
    Ok(state)
}

/// Match Atuin's builder; background WAL compaction is outside this isolated capture.
pub async fn open(path: &Path) -> Result<SqlitePool, sqlx::Error> {
    let options = SqliteConnectOptions::new().filename(path).create_if_missing(true)
        .optimize_on_close(true,None).synchronous(SqliteSynchronous::Normal)
        .foreign_keys(true).journal_mode(SqliteJournalMode::Wal)
        .pragma("journal_size_limit","4194304").with_regexp();
    SqlitePoolOptions::new().acquire_timeout(Duration::from_secs(5))
        .connect_with(options).await
}
