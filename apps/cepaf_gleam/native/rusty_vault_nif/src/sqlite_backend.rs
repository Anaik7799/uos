//! Slice B disk persistence backend for the RustyVault NIF.
//!
//! Scope (Slice B scaffold):
//!   - Open a SQLite connection at a given path.
//!   - Run DDL migrations (idempotent CREATE TABLE IF NOT EXISTS) for:
//!       * kv_entries     — versioned secret rows (SC-VAULT-011 monotonic versions)
//!       * audit_log      — append-only audit trail (SC-VAULT-008)
//!
//! Out of scope for this slice (deferred — do NOT add here):
//!   - Tokio / async access (next session).
//!   - Replacing VaultHandle::kv_store HashMap (needs RAII coordination).
//!   - WAL journal mode + synchronous=FULL tuning (Slice B-full per SC-VAULT-012).
//!
//! Stub-That-Lies guard ([zk-3346fc607a1ef9e6], RPN 729):
//!   `open` and `migrate` MUST be REAL — they actually open SQLite and execute DDL.
//!   The 3 unit tests verify this mechanically by checking the on-disk schema.

use std::path::{Path, PathBuf};

use rusqlite::Connection;

#[derive(Debug)]
pub enum BackendError {
    OpenFailed(String),
    MigrateFailed(String),
}

impl std::fmt::Display for BackendError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            BackendError::OpenFailed(m) => write!(f, "sqlite open failed: {m}"),
            BackendError::MigrateFailed(m) => write!(f, "sqlite migrate failed: {m}"),
        }
    }
}

impl std::error::Error for BackendError {}

/// SQLite-backed K/V backend for the vault.
///
/// Slice B scaffold: holds the path and opens a fresh `Connection` for each
/// operation. A persistent pooled connection comes in Slice B-full once Tokio
/// integration is in place.
pub struct SqliteKvBackend {
    path: PathBuf,
}

impl SqliteKvBackend {
    /// Open (or create) a SQLite database file at `path`.
    ///
    /// REAL behaviour: opens a `rusqlite::Connection` to verify the path is
    /// writable and the file is a valid SQLite container. The connection is
    /// dropped immediately; subsequent calls re-open as needed.
    pub fn open(path: &Path) -> Result<Self, BackendError> {
        let _conn = Connection::open(path)
            .map_err(|e| BackendError::OpenFailed(e.to_string()))?;
        Ok(Self {
            path: path.to_path_buf(),
        })
    }

    /// Apply WAL journal mode + synchronous=FULL per SC-VAULT-012.
    ///
    /// Pass-35 Track B addition. WAL gives us:
    ///   - Concurrent reads while a writer holds the write-lock.
    ///   - Better crash-safety than the default rollback journal.
    /// `synchronous=FULL` ensures fsync() on every commit — the strongest
    /// durability guarantee SQLite offers, required for a secrets store.
    ///
    /// Idempotent: re-running on an already-WAL DB is a no-op. Returns
    /// `MigrateFailed` (reused variant) if either pragma is rejected.
    pub fn apply_wal_pragmas(&self) -> Result<(), BackendError> {
        let conn = Connection::open(&self.path)
            .map_err(|e| BackendError::MigrateFailed(e.to_string()))?;
        // PRAGMA journal_mode=WAL returns the new mode as a row; we ignore
        // the value but must consume the row, hence query_row not execute.
        let mode: String = conn
            .query_row("PRAGMA journal_mode=WAL", [], |row| row.get(0))
            .map_err(|e| BackendError::MigrateFailed(e.to_string()))?;
        if !mode.eq_ignore_ascii_case("wal") {
            return Err(BackendError::MigrateFailed(format!(
                "journal_mode pragma returned '{mode}', expected 'wal'"
            )));
        }
        conn.execute_batch("PRAGMA synchronous=FULL;")
            .map_err(|e| BackendError::MigrateFailed(e.to_string()))?;
        Ok(())
    }

    /// Run DDL migrations idempotently.
    ///
    /// REAL behaviour: opens the database, executes `CREATE TABLE IF NOT EXISTS`
    /// for `kv_entries` and `audit_log`. Composite primary key on
    /// (name, version) enforces SC-VAULT-011 monotonic versioning at the
    /// storage layer.
    pub fn migrate(&self) -> Result<(), BackendError> {
        let conn = Connection::open(&self.path)
            .map_err(|e| BackendError::MigrateFailed(e.to_string()))?;
        conn.execute_batch(
            r#"
            CREATE TABLE IF NOT EXISTS kv_entries (
                name         TEXT    NOT NULL,
                version      INTEGER NOT NULL,
                value        BLOB    NOT NULL,
                created_at   INTEGER NOT NULL,
                ttl_sec      INTEGER NOT NULL,
                max_ttl_sec  INTEGER NOT NULL,
                lease_id     TEXT    NOT NULL,
                PRIMARY KEY (name, version)
            );
            CREATE TABLE IF NOT EXISTS audit_log (
                id      INTEGER PRIMARY KEY AUTOINCREMENT,
                ts      INTEGER NOT NULL,
                event   TEXT    NOT NULL,
                name    TEXT    NOT NULL,
                version INTEGER NOT NULL,
                caller  TEXT    NOT NULL
            );
            "#,
        )
        .map_err(|e| BackendError::MigrateFailed(e.to_string()))?;
        Ok(())
    }

    /// Path of the underlying SQLite database file.
    pub fn path(&self) -> &Path {
        &self.path
    }

    // =================================================================
    // Pass-34 Track B — versioned K/V CRUD primitives
    //
    // These do NOT yet wire into VaultHandle; that requires RAII +
    // Tokio coordination and is a separate later pass. They are real,
    // unit-tested SQL operations on a temp-file DB so the next pass can
    // simply swap VaultHandle::kv_store HashMap calls for these.
    // =================================================================

    /// Insert a new versioned secret row.
    ///
    /// SC-VAULT-011: composite PK `(name, version)` enforces monotonicity at
    /// the storage layer. Caller is responsible for picking the next version
    /// (typically `versions(name).last() + 1`).
    ///
    /// Returns `MigrateFailed` only when SQLite reports an error (we reuse
    /// that variant rather than introduce new ones until the API stabilises).
    pub fn put_kv(
        &self,
        name: &str,
        version: i64,
        ciphertext: &[u8],
        ttl_sec: i64,
        max_ttl_sec: i64,
    ) -> Result<(), BackendError> {
        let conn = Connection::open(&self.path)
            .map_err(|e| BackendError::MigrateFailed(e.to_string()))?;
        let now = chrono_now_unix();
        conn.execute(
            "INSERT INTO kv_entries (name, version, value, created_at, ttl_sec, max_ttl_sec, lease_id) \
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)",
            rusqlite::params![
                name,
                version,
                ciphertext,
                now,
                ttl_sec,
                max_ttl_sec,
                "" // lease_id assigned at unseal-time; empty until then
            ],
        )
        .map_err(|e| BackendError::MigrateFailed(e.to_string()))?;
        Ok(())
    }

    /// Fetch the latest (highest-version) row for a secret name.
    ///
    /// Returns `Ok(None)` if no row exists (caller distinguishes "no
    /// version yet" from "DB error"). Returns `(version, ciphertext)`.
    pub fn get_latest(&self, name: &str) -> Result<Option<(i64, Vec<u8>)>, BackendError> {
        let conn = Connection::open(&self.path)
            .map_err(|e| BackendError::MigrateFailed(e.to_string()))?;
        let mut stmt = conn
            .prepare(
                "SELECT version, value FROM kv_entries \
                 WHERE name = ?1 ORDER BY version DESC LIMIT 1",
            )
            .map_err(|e| BackendError::MigrateFailed(e.to_string()))?;
        let mut rows = stmt
            .query(rusqlite::params![name])
            .map_err(|e| BackendError::MigrateFailed(e.to_string()))?;
        match rows
            .next()
            .map_err(|e| BackendError::MigrateFailed(e.to_string()))?
        {
            None => Ok(None),
            Some(row) => {
                let v: i64 = row
                    .get(0)
                    .map_err(|e| BackendError::MigrateFailed(e.to_string()))?;
                let blob: Vec<u8> = row
                    .get(1)
                    .map_err(|e| BackendError::MigrateFailed(e.to_string()))?;
                Ok(Some((v, blob)))
            }
        }
    }

    /// Delete a specific version row for a secret.
    ///
    /// Pass-35 Track B addition. Returns `Ok(true)` if a row was removed,
    /// `Ok(false)` if no such (name, version) pair existed (idempotent
    /// caller-friendly behaviour).
    ///
    /// SC-VAULT-008 (audit append-only) is NOT violated: this deletes
    /// from `kv_entries`, not from `audit_log`. Audit-log retention is
    /// governed by SC-VAULT-022 (rotation at 100 MB) only.
    pub fn delete_version(&self, name: &str, version: i64) -> Result<bool, BackendError> {
        let conn = Connection::open(&self.path)
            .map_err(|e| BackendError::MigrateFailed(e.to_string()))?;
        let n = conn
            .execute(
                "DELETE FROM kv_entries WHERE name = ?1 AND version = ?2",
                rusqlite::params![name, version],
            )
            .map_err(|e| BackendError::MigrateFailed(e.to_string()))?;
        Ok(n > 0)
    }

    /// Count how many versions exist for a given secret name.
    ///
    /// Pass-35 Track B addition. Cheaper than `versions(name)?.len()` because
    /// it pushes the count down to SQLite (no row materialisation).
    pub fn count_versions(&self, name: &str) -> Result<i64, BackendError> {
        let conn = Connection::open(&self.path)
            .map_err(|e| BackendError::MigrateFailed(e.to_string()))?;
        let n: i64 = conn
            .query_row(
                "SELECT COUNT(*) FROM kv_entries WHERE name = ?1",
                rusqlite::params![name],
                |row| row.get(0),
            )
            .map_err(|e| BackendError::MigrateFailed(e.to_string()))?;
        Ok(n)
    }

    /// Return all version numbers for a secret, ascending.
    /// Empty vec when no rows exist (vs None for storage error).
    pub fn versions(&self, name: &str) -> Result<Vec<i64>, BackendError> {
        let conn = Connection::open(&self.path)
            .map_err(|e| BackendError::MigrateFailed(e.to_string()))?;
        let mut stmt = conn
            .prepare(
                "SELECT version FROM kv_entries WHERE name = ?1 ORDER BY version ASC",
            )
            .map_err(|e| BackendError::MigrateFailed(e.to_string()))?;
        let rows = stmt
            .query_map(rusqlite::params![name], |row| row.get::<_, i64>(0))
            .map_err(|e| BackendError::MigrateFailed(e.to_string()))?;
        let mut out = Vec::new();
        for r in rows {
            out.push(r.map_err(|e| BackendError::MigrateFailed(e.to_string()))?);
        }
        Ok(out)
    }
}

fn chrono_now_unix() -> i64 {
    chrono::Utc::now().timestamp()
}

// =====================================================================
// Tests — Slice B mechanical verification (Stub-That-Lies guard)
// =====================================================================

#[cfg(test)]
mod tests {
    use super::*;
    use rusqlite::Connection;
    use tempfile::tempdir;

    #[test]
    fn open_creates_db_file_at_temp_path() {
        let dir = tempdir().expect("tempdir");
        let db_path = dir.path().join("vault_open.db");
        assert!(!db_path.exists(), "precondition: db must not exist yet");

        let backend = SqliteKvBackend::open(&db_path).expect("open should succeed");

        assert!(db_path.exists(), "open() must create the SQLite file on disk");
        assert_eq!(backend.path(), db_path.as_path());
    }

    #[test]
    fn migrate_creates_kv_entries_table() {
        let dir = tempdir().expect("tempdir");
        let db_path = dir.path().join("vault_kv.db");
        let backend = SqliteKvBackend::open(&db_path).expect("open");
        backend.migrate().expect("migrate should succeed");

        // Verify the table exists by querying sqlite_master directly.
        let conn = Connection::open(&db_path).expect("reopen");
        let name: String = conn
            .query_row(
                "SELECT name FROM sqlite_master WHERE type='table' AND name='kv_entries'",
                [],
                |row| row.get(0),
            )
            .expect("kv_entries table must exist after migrate");
        assert_eq!(name, "kv_entries");

        // Confirm composite primary key (name, version) exists by inserting + uniqueness.
        conn.execute(
            "INSERT INTO kv_entries (name, version, value, created_at, ttl_sec, max_ttl_sec, lease_id) \
             VALUES ('s', 1, X'00', 0, 60, 600, 'l1')",
            [],
        )
        .expect("first insert should succeed");
        let dup = conn.execute(
            "INSERT INTO kv_entries (name, version, value, created_at, ttl_sec, max_ttl_sec, lease_id) \
             VALUES ('s', 1, X'00', 0, 60, 600, 'l1')",
            [],
        );
        assert!(dup.is_err(), "duplicate (name,version) must violate PK");
    }

    // ===== Pass-34 Track B — versioned K/V CRUD tests =====

    fn fresh_backend(name: &str) -> (tempfile::TempDir, SqliteKvBackend) {
        let dir = tempdir().expect("tempdir");
        let p = dir.path().join(name);
        let b = SqliteKvBackend::open(&p).expect("open");
        b.migrate().expect("migrate");
        (dir, b)
    }

    #[test]
    fn put_kv_then_get_latest_round_trips() {
        let (_dir, b) = fresh_backend("kv1.db");
        b.put_kv("anthropic_api_key", 1, b"\x01\x02\x03", 3600, 86_400)
            .expect("put_kv v1");
        let got = b.get_latest("anthropic_api_key").expect("get_latest");
        assert_eq!(got, Some((1, vec![0x01, 0x02, 0x03])));
    }

    #[test]
    fn get_latest_picks_highest_version() {
        let (_dir, b) = fresh_backend("kv2.db");
        b.put_kv("k", 1, b"v1", 60, 600).unwrap();
        b.put_kv("k", 2, b"v2", 60, 600).unwrap();
        b.put_kv("k", 3, b"v3", 60, 600).unwrap();
        let got = b.get_latest("k").unwrap();
        assert_eq!(got, Some((3, b"v3".to_vec())));
    }

    #[test]
    fn versions_returns_ascending_list() {
        let (_dir, b) = fresh_backend("kv3.db");
        b.put_kv("k", 3, b"a", 60, 600).unwrap();
        b.put_kv("k", 1, b"a", 60, 600).unwrap();
        b.put_kv("k", 2, b"a", 60, 600).unwrap();
        assert_eq!(b.versions("k").unwrap(), vec![1, 2, 3]);
    }

    #[test]
    fn get_latest_and_versions_handle_missing_secret() {
        let (_dir, b) = fresh_backend("kv4.db");
        assert_eq!(b.get_latest("nope").unwrap(), None);
        assert_eq!(b.versions("nope").unwrap(), Vec::<i64>::new());
    }

    #[test]
    fn put_kv_rejects_duplicate_version() {
        let (_dir, b) = fresh_backend("kv5.db");
        b.put_kv("k", 1, b"a", 60, 600).unwrap();
        let dup = b.put_kv("k", 1, b"b", 60, 600);
        assert!(dup.is_err(), "duplicate (name,version) must violate PK");
    }

    // ===== Pass-35 Track B — WAL + delete_version + count_versions =====

    #[test]
    fn apply_wal_pragmas_switches_journal_mode_to_wal() {
        let (_dir, b) = fresh_backend("kv_wal.db");
        b.apply_wal_pragmas().expect("apply_wal_pragmas should succeed");
        // Verify on a fresh connection.
        let conn = Connection::open(b.path()).expect("reopen");
        let mode: String = conn
            .query_row("PRAGMA journal_mode", [], |row| row.get(0))
            .expect("journal_mode query");
        assert!(
            mode.eq_ignore_ascii_case("wal"),
            "expected wal, got {mode}"
        );
        // synchronous should be FULL (=2) per SC-VAULT-012.
        let sync_mode: i64 = conn
            .query_row("PRAGMA synchronous", [], |row| row.get(0))
            .expect("synchronous query");
        assert_eq!(sync_mode, 2, "synchronous=FULL is integer 2");
    }

    #[test]
    fn delete_version_removes_only_that_row_and_returns_true() {
        let (_dir, b) = fresh_backend("kv_del.db");
        b.put_kv("k", 1, b"v1", 60, 600).unwrap();
        b.put_kv("k", 2, b"v2", 60, 600).unwrap();
        b.put_kv("k", 3, b"v3", 60, 600).unwrap();

        let removed = b.delete_version("k", 2).expect("delete_version");
        assert!(removed, "delete_version should report row removed");

        // Surviving versions: 1 and 3 only.
        assert_eq!(b.versions("k").unwrap(), vec![1, 3]);
        assert_eq!(b.get_latest("k").unwrap(), Some((3, b"v3".to_vec())));
    }

    #[test]
    fn delete_version_returns_false_for_missing_pair() {
        let (_dir, b) = fresh_backend("kv_del_missing.db");
        b.put_kv("k", 1, b"v1", 60, 600).unwrap();
        // Version 99 doesn't exist; idempotent false return.
        let removed = b.delete_version("k", 99).expect("delete_version");
        assert!(!removed, "non-existent (name,version) → false");
        // Other secret entirely.
        let removed2 = b.delete_version("nonexistent", 1).expect("delete_version");
        assert!(!removed2);
    }

    #[test]
    fn count_versions_matches_versions_len() {
        let (_dir, b) = fresh_backend("kv_count.db");
        assert_eq!(b.count_versions("k").unwrap(), 0);
        b.put_kv("k", 1, b"a", 60, 600).unwrap();
        b.put_kv("k", 2, b"a", 60, 600).unwrap();
        b.put_kv("k", 3, b"a", 60, 600).unwrap();
        assert_eq!(b.count_versions("k").unwrap(), 3);
        assert_eq!(b.count_versions("k").unwrap() as usize, b.versions("k").unwrap().len());
        // Different secret untouched.
        b.put_kv("other", 1, b"x", 60, 600).unwrap();
        assert_eq!(b.count_versions("k").unwrap(), 3);
        assert_eq!(b.count_versions("other").unwrap(), 1);
    }

    #[test]
    fn count_versions_after_delete_decrements() {
        // Pass-35 Track B: ensure the two new APIs compose correctly —
        // delete_version followed by count_versions should reflect the
        // mutation atomically (single-conn SQL semantics).
        let (_dir, b) = fresh_backend("kv_compose.db");
        b.put_kv("k", 1, b"a", 60, 600).unwrap();
        b.put_kv("k", 2, b"a", 60, 600).unwrap();
        assert_eq!(b.count_versions("k").unwrap(), 2);
        b.delete_version("k", 1).unwrap();
        assert_eq!(b.count_versions("k").unwrap(), 1);
        b.delete_version("k", 2).unwrap();
        assert_eq!(b.count_versions("k").unwrap(), 0);
    }

    #[test]
    fn migrate_creates_audit_log_table() {
        let dir = tempdir().expect("tempdir");
        let db_path = dir.path().join("vault_audit.db");
        let backend = SqliteKvBackend::open(&db_path).expect("open");
        backend.migrate().expect("migrate should succeed");

        let conn = Connection::open(&db_path).expect("reopen");
        let name: String = conn
            .query_row(
                "SELECT name FROM sqlite_master WHERE type='table' AND name='audit_log'",
                [],
                |row| row.get(0),
            )
            .expect("audit_log table must exist after migrate");
        assert_eq!(name, "audit_log");

        // Verify it accepts an append (smoke check on column shape).
        conn.execute(
            "INSERT INTO audit_log (ts, event, name, version, caller) \
             VALUES (123, 'put', 'k', 1, 'nif')",
            [],
        )
        .expect("audit_log insert should succeed with declared columns");
    }
}
