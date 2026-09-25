//! Explicit schema-preserving fault instrumentation, never default Atuin configuration.
use std::ffi::{CStr, c_char, c_int, c_void};
use std::sync::atomic::{AtomicUsize, Ordering};
use sqlx::SqliteConnection;

/// Count actual intercepted preparations rather than assuming the hook was exercised.
static DENIED_TIMING_UPDATES: AtomicUsize = AtomicUsize::new(0);

/// Deny precisely SQLx's post-commit elapsed-time write, leaving all schema intact.
unsafe extern "C" fn authorizer(_context: *mut c_void, action: c_int,
    table: *const c_char, column: *const c_char, _database: *const c_char,
    _trigger: *const c_char) -> c_int {
    if action == libsqlite3_sys::SQLITE_UPDATE && !table.is_null() && !column.is_null() {
        // SQLite owns these zero-terminated callback arguments during this invocation.
        let denied = unsafe { CStr::from_ptr(table).to_bytes() == b"_sqlx_migrations" &&
            CStr::from_ptr(column).to_bytes() == b"execution_time" };
        if denied {
            DENIED_TIMING_UPDATES.fetch_add(1,Ordering::Relaxed);
            return libsqlite3_sys::SQLITE_DENY;
        }
    }
    libsqlite3_sys::SQLITE_OK
}

/// Install instrumentation under SQLx's worker-excluding native-handle guard.
pub async fn deny_timing_updates(connection: &mut SqliteConnection) -> Result<(), sqlx::Error> {
    let mut handle = connection.lock_handle().await?;
    DENIED_TIMING_UPDATES.store(0,Ordering::Relaxed);
    // The callback has static lifetime; it carries no borrowed or mutable context.
    let result = unsafe { libsqlite3_sys::sqlite3_set_authorizer(
        handle.as_raw_handle().as_ptr(),Some(authorizer),std::ptr::null_mut()) };
    assert_eq!(result,libsqlite3_sys::SQLITE_OK);
    Ok(())
}

/// Export observed instrumentation activity with each trace.
pub fn denied_timing_updates() -> usize {
    DENIED_TIMING_UPDATES.load(Ordering::Relaxed)
}
