//! Execute the complete real-runner capture.
use atuin_sqlx_capture::{closed_snapshot, open, profile, snapshot};
use serde_json::json;
use sqlx::Connection;
use std::{error::Error, path::Path};

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
    drop(conn);
    pool.close().await;
    let persisted_baseline = closed_snapshot(path).await?;
    let pool = open(path).await?;
    let mut conn = pool.acquire().await?;
    let engine = profile(&mut conn).await?;
    let before = snapshot(&mut conn).await?;
    drop(conn);
    migrator.run(&pool).await?;
    let mut conn = pool.acquire().await?;
    conn.clear_cached_statements().await?;
    let after = snapshot(&mut conn).await?;
    drop(conn);
    pool.close().await;
    let post_close = closed_snapshot(path).await?;
    println!("{}",serde_json::to_string_pretty(&json!({
        "capture_kind":"real-sqlx-runner-harness",
        "atuin_revision":"5b10eb09c664d316b7384210399b02e6127f4027",
        "sqlx_version":"0.9.0","profile":engine,"before":before,"after":after,
        "persisted_baseline":persisted_baseline,"post_close":post_close
    }))?);
    Ok(())
}
