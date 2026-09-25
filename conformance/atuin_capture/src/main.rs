//! Capture the pinned real SQLx migrator with Atuin's logical connection profile.
use serde_json::{Value, json};
use sqlx::sqlite::{SqliteConnectOptions, SqliteJournalMode, SqlitePoolOptions, SqliteSynchronous};
use sqlx::{AssertSqlSafe, Connection, Row, SqliteConnection, SqlitePool};
use std::{error::Error, path::Path, time::Duration};

/// Export every schema object, including implicit indexes and SQLx bookkeeping.
async fn snapshot(conn: &mut SqliteConnection) -> Result<Value, sqlx::Error> {
    let rows = sqlx::query("SELECT type,name,tbl_name,rootpage,sql FROM sqlite_schema ORDER BY type,name")
        .fetch_all(&mut *conn).await?;
    let schema: Vec<Value> = rows.iter().map(|row| json!({
        "type": row.get::<String,_>(0), "name": row.get::<String,_>(1),
        "table": row.get::<String,_>(2), "rootpage": row.get::<i64,_>(3),
        "sql": row.get::<Option<String>,_>(4)
    })).collect();
    let rows = sqlx::query("SELECT version,description,installed_on,success,hex(checksum),execution_time FROM _sqlx_migrations ORDER BY version")
        .fetch_all(&mut *conn).await?;
    let metadata: Vec<Value> = rows.iter().map(|row| json!({
        "version": row.get::<i64,_>(0), "description": row.get::<String,_>(1),
        "installed_on": row.get::<String,_>(2), "success": row.get::<i64,_>(3),
        "checksum_hex": row.get::<String,_>(4), "execution_time": row.get::<i64,_>(5)
    })).collect();
    Ok(json!({"schema":schema,"metadata":metadata}))
}

/// Record the actual linked engine and effective connection PRAGMAs.
async fn profile(conn: &mut SqliteConnection) -> Result<Value, sqlx::Error> {
    let row = sqlx::query("SELECT sqlite_version(),sqlite_source_id()")
        .fetch_one(&mut *conn).await?;
    let options: Vec<String> = sqlx::query_scalar("PRAGMA compile_options")
        .fetch_all(&mut *conn).await?;
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
    Ok(json!({"sqlite_version":row.get::<String,_>(0),
        "sqlite_source_id":row.get::<String,_>(1),"compile_options":options,"pragmas":pragmas}))
}

/// Match Atuin's builder; background WAL compaction is outside this isolated capture.
async fn open(path: &Path) -> Result<SqlitePool, sqlx::Error> {
    let options = SqliteConnectOptions::new().filename(path).create_if_missing(true)
        .optimize_on_close(true,None).synchronous(SqliteSynchronous::Normal)
        .foreign_keys(true).journal_mode(SqliteJournalMode::Wal)
        .pragma("journal_size_limit","4194304").with_regexp();
    SqlitePoolOptions::new().acquire_timeout(Duration::from_secs(5))
        .connect_with(options).await
}

/// Run the actual upstream migration API, preserving original migration bytes.
#[tokio::main]
async fn main() -> Result<(), Box<dyn Error>> {
    let args: Vec<String> = std::env::args().collect();
    if args.len() != 3 { return Err("usage: atuin-sqlx-capture NEW_DATABASE MIGRATIONS_DIR".into()); }
    let path = Path::new(&args[1]);
    if path.exists() { return Err("capture refuses to overwrite an existing database".into()); }
    let migrator = sqlx::migrate::Migrator::new(Path::new(&args[2])).await?;
    let pool = open(path).await?;
    migrator.run_to(20260224000100,&pool).await?;
    let mut conn = pool.acquire().await?;
    conn.clear_cached_statements().await?;
    let engine = profile(&mut conn).await?;
    let before = snapshot(&mut conn).await?;
    drop(conn);
    migrator.run(&pool).await?;
    let mut conn = pool.acquire().await?;
    conn.clear_cached_statements().await?;
    let after = snapshot(&mut conn).await?;
    drop(conn);
    pool.close().await;
    println!("{}",serde_json::to_string_pretty(&json!({
        "capture_kind":"real-sqlx-runner-harness",
        "atuin_revision":"5b10eb09c664d316b7384210399b02e6127f4027",
        "sqlx_version":"0.9.0","profile":engine,"before":before,"after":after
    }))?);
    Ok(())
}
