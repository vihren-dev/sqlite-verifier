//! Observe real SQLx rollback and post-commit errors on native SQLite witnesses.
use atuin_sqlx_capture::{closed_snapshot, open, profile, snapshot};
use serde_json::{Value, json};
use sqlx::{AssertSqlSafe, Connection, Row, SqliteConnection};
use std::{error::Error, path::Path};

/// Preserve SQLite storage classes and byte representations in observations.
async fn history(conn: &mut SqliteConnection) -> Result<Value, sqlx::Error> {
    let mut expressions = vec!["rowid".to_owned()];
    for column in ["id", "timestamp", "duration", "exit", "command", "cwd",
        "session", "hostname", "deleted_at", "author", "intent"] {
        expressions.push(format!("typeof({column})"));
        expressions.push(format!("quote({column})"));
        expressions.push(format!("hex(CAST({column} AS BLOB))"));
    }
    let sql = format!("SELECT {} FROM history ORDER BY rowid", expressions.join(","));
    let rows = sqlx::query(AssertSqlSafe(sql)).fetch_all(conn).await?;
    Ok(json!(rows.iter().map(|row| {
        let mut values = vec![json!(row.get::<i64,_>(0))];
        for index in 1..34 { values.push(json!(row.get::<String,_>(index))); }
        values
    }).collect::<Vec<_>>()))
}

/// Fault triggers are experimental perturbations, not admitted pilot schemas.
async fn inject(conn: &mut SqliteConnection, scenario: &str) -> Result<(), Box<dyn Error>> {
    if scenario == "timing_authorizer_failure" {
        atuin_sqlx_capture::faults::deny_timing_updates(conn).await?;
        return Ok(());
    }
    let sql = match scenario {
        "success" | "payload_failure" | "already_applied" => return Ok(()),
        "metadata_insert_failure" => "CREATE TRIGGER reject_metadata BEFORE INSERT ON _sqlx_migrations BEGIN SELECT RAISE(ABORT,'injected metadata insert failure'); END",
        "timing_update_failure" => "CREATE TRIGGER reject_timing BEFORE UPDATE OF execution_time ON _sqlx_migrations BEGIN SELECT RAISE(ABORT,'injected timing update failure'); END",
        "dirty_metadata" => "UPDATE _sqlx_migrations SET success=0 WHERE version=20260224000100",
        "checksum_mismatch" => "UPDATE _sqlx_migrations SET checksum=X'00' WHERE version=20260224000100",
        "unknown_version" => "INSERT INTO _sqlx_migrations(version,description,success,checksum,execution_time) VALUES(42,'unknown',1,X'00',0)",
        _ => return Err("unknown scenario".into()),
    };
    sqlx::query(AssertSqlSafe(sql)).execute(conn).await?;
    Ok(())
}

/// Run a selected perturbation against a fresh complete baseline with legal edge rows.
#[tokio::main]
async fn main() -> Result<(), Box<dyn Error>> {
    let args: Vec<String> = std::env::args().collect();
    if args.len()!=4 && args.len()!=5 {
        return Err("usage: adversarial NEW_DB MIGRATIONS SCENARIO [0|1|3]".into());
    }
    if Path::new(&args[1]).exists() { return Err("database must not exist".into()); }
    let migrator = sqlx::migrate::Migrator::new(Path::new(&args[2])).await?;
    let pool = open(Path::new(&args[1])).await?;
    migrator.run_to(20260224000100,&pool).await?;
    let mut conn = pool.acquire().await?;
    // Two NULL text PKs, signed rowid extremes, TEXT/BLOB in INTEGER columns,
    // embedded NUL text, non-UTF8 BLOB, and numeric TEXT-affinity conversions.
    sqlx::query("INSERT INTO history(rowid,id,timestamp,duration,exit,command,cwd,session,hostname,deleted_at,author,intent) VALUES(-9223372036854775808,NULL,1,'not-an-integer',X'00FF','same','/a','session','host',NULL,NULL,NULL),(-1,NULL,2,1.25,0,'same','/a','session','host','unparsed',X'80FF',CAST(X'610062' AS TEXT)),(9223372036854775807,'',X'0102',-2,0,X'00FF',123,456,789,NULL,'author','intent')")
        .execute(&mut *conn).await?;
    match args.get(4).map(String::as_str).unwrap_or("3") {
        "0" => { sqlx::query("DELETE FROM history").execute(&mut *conn).await?; }
        "1" => { sqlx::query("DELETE FROM history WHERE rowid != -9223372036854775808")
            .execute(&mut *conn).await?; }
        "3" => (),
        _ => return Err("row count must be 0, 1 or 3".into()),
    }
    drop(conn);
    pool.close().await;
    let pool = open(Path::new(&args[1])).await?;
    let mut conn = pool.acquire().await?;
    let engine = profile(&mut conn).await?;
    drop(conn);
    if args[3]=="already_applied" { migrator.run(&pool).await?; }
    let mut conn = pool.acquire().await?;
    inject(&mut conn,&args[3]).await?;
    let before = snapshot(&mut conn).await?;
    let old_history = history(&mut conn).await?;
    let outcome = migrator.run(&mut *conn).await;
    // Successful cache clearing is observed; no fictitious cache-failure injection.
    conn.clear_cached_statements().await?;
    let after = snapshot(&mut conn).await?;
    let new_history = history(&mut conn).await?;
    let has_shell: i64 = sqlx::query_scalar("SELECT count(*) FROM pragma_table_info('history') WHERE name='shell'")
        .fetch_one(&mut *conn).await?;
    let shell_nulls: Option<i64> = if has_shell==1 {
        Some(sqlx::query_scalar("SELECT count(*) FROM history WHERE shell IS NULL")
            .fetch_one(&mut *conn).await?)
    } else { None };
    let integrity: String = sqlx::query_scalar("PRAGMA integrity_check").fetch_one(&mut *conn).await?;
    drop(conn);
    pool.close().await;
    let post_close = closed_snapshot(Path::new(&args[1])).await?;
    let options = sqlx::sqlite::SqliteConnectOptions::new().filename(&args[1]).read_only(true);
    let mut reader = SqliteConnection::connect_with(&options).await?;
    let post_close_history = history(&mut reader).await?;
    reader.close().await?;
    println!("{}",serde_json::to_string_pretty(&json!({
        "scenario":args[3],"profile":engine,"error":outcome.err().map(|e|e.to_string()),
        "before":before,"after":after,"history_before":old_history,
        "history_after":new_history,"shell_nulls":shell_nulls,"integrity_check":integrity,
        "post_close":post_close,"post_close_history":post_close_history,
        "instrumentation": if args[3]=="timing_authorizer_failure" {
            json!({"kind":"SQLITE_AUTHORIZER","denied_table":"_sqlx_migrations",
                "denied_column":"execution_time","denied_updates":
                atuin_sqlx_capture::faults::denied_timing_updates()})
        } else { Value::Null }
    }))?);
    Ok(())
}
