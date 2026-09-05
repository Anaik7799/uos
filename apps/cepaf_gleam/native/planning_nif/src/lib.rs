//! # Planning NIF — SQLite Task Management for BEAM/Gleam
//!
//! Exposes sa-plan-daemon's Planning.db as Erlang NIFs callable from Gleam
//! via @external(erlang, "planning_nif", ...).
//!
//! Reuses db.rs patterns from planning_daemon: WAL mode, 5s busy timeout,
//! exponential backoff with jitter for lock contention.
//!
//! STAMP: SC-TODO-001, SC-ARCH-SPLIT-003, SC-NIF-001, SC-ZMOF-005

use rand::Rng;
use rusqlite::{params, Connection};
use rustler::NifResult;
use serde::Serialize;
use std::time::Duration;

rustler::init!("planning_nif");

// ---------------------------------------------------------------------------
// DB path — authoritative Smriti.db with 867 tasks
// ---------------------------------------------------------------------------

fn db_path() -> String {
    // Try env var first, then known absolute paths, then relative
    if let Ok(p) = std::env::var("PLANNING_DB_PATH") {
        return p;
    }
    let candidates = [
        "sub-projects/c3i/data/smriti/Smriti.db",
        "../../sub-projects/c3i/data/smriti/Smriti.db",
        "/home/an/dev/ver/c3i/sub-projects/c3i/data/smriti/Smriti.db",
    ];
    for c in &candidates {
        if std::path::Path::new(c).exists() {
            return c.to_string();
        }
    }
    candidates[2].to_string()
}

// ---------------------------------------------------------------------------
// Types (mirrors planning_daemon/src/db.rs Task struct)
// ---------------------------------------------------------------------------

#[derive(Debug, Serialize)]
struct Task {
    id: String,
    title: String,
    status: String,
    priority: String,
    parent_id: Option<String>,
    owner: Option<String>,
    created: String,
}

#[derive(Debug, Serialize)]
struct StatusCounts {
    active: usize,
    pending: usize,
    completed: usize,
    blocked: usize,
    total: usize,
}

// ---------------------------------------------------------------------------
// DB helpers (reused from planning_daemon/src/db.rs)
// ---------------------------------------------------------------------------

fn open_db() -> Result<Connection, String> {
    let conn = Connection::open(&db_path())
        .map_err(|e| format!("SQLite open error: {}", e))?;
    conn.execute("PRAGMA journal_mode=WAL", []).ok();
    conn.busy_timeout(Duration::from_millis(5000)).ok();
    Ok(conn)
}

fn execute_with_backoff<F, T>(mut op: F) -> Result<T, String>
where
    F: FnMut() -> Result<T, rusqlite::Error>,
{
    let mut attempts = 0u32;
    let max_attempts = 10;
    let mut rng = rand::thread_rng();

    loop {
        match op() {
            Ok(result) => return Ok(result),
            Err(e) => {
                let msg = e.to_string();
                if (msg.contains("database is locked") || msg.contains("database is busy"))
                    && attempts < max_attempts
                {
                    attempts += 1;
                    let backoff = (2u64.pow(attempts) * 10) + rng.gen_range(0..20);
                    std::thread::sleep(Duration::from_millis(backoff));
                } else {
                    return Err(format!("SQLite error: {}", e));
                }
            }
        }
    }
}

fn query_all_tasks(conn: &Connection) -> Result<Vec<Task>, String> {
    execute_with_backoff(|| {
        let mut stmt = conn.prepare(
            "SELECT Id, Title, Status, Priority, ParentId, Owner, Created \
             FROM Tasks ORDER BY Created ASC, Id ASC",
        )?;
        let rows = stmt.query_map([], |row| {
            Ok(Task {
                id: row.get(0)?,
                title: row.get(1)?,
                status: row.get(2)?,
                priority: row.get(3)?,
                parent_id: row.get(4)?,
                owner: row.get(5)?,
                created: row.get(6)?,
            })
        })?;
        let mut tasks = Vec::new();
        for r in rows {
            tasks.push(r?);
        }
        Ok(tasks)
    })
}

// ---------------------------------------------------------------------------
// NIF 1: plan_status — task count summary
// ---------------------------------------------------------------------------

#[rustler::nif(schedule = "DirtyCpu")]
fn plan_status() -> NifResult<String> {
    let conn = open_db().map_err(|e| rustler::Error::Term(Box::new(e)))?;
    let tasks = query_all_tasks(&conn).map_err(|e| rustler::Error::Term(Box::new(e)))?;

    let counts = StatusCounts {
        active: tasks.iter().filter(|t| t.status == "in_progress").count(),
        pending: tasks.iter().filter(|t| t.status == "pending").count(),
        completed: tasks.iter().filter(|t| t.status == "completed").count(),
        blocked: tasks.iter().filter(|t| t.status == "blocked").count(),
        total: tasks.len(),
    };
    Ok(serde_json::to_string(&counts).unwrap_or_else(|_| "{}".into()))
}

// ---------------------------------------------------------------------------
// NIF 2: plan_list_pending — all non-completed tasks
// ---------------------------------------------------------------------------

#[rustler::nif(schedule = "DirtyCpu")]
fn plan_list_pending() -> NifResult<String> {
    let conn = open_db().map_err(|e| rustler::Error::Term(Box::new(e)))?;
    let tasks = query_all_tasks(&conn).map_err(|e| rustler::Error::Term(Box::new(e)))?;
    let pending: Vec<&Task> = tasks
        .iter()
        .filter(|t| t.status != "completed")
        .collect();
    Ok(serde_json::to_string(&pending).unwrap_or_else(|_| "[]".into()))
}

// ---------------------------------------------------------------------------
// NIF 3: plan_list_by_status — filter by status string
// ---------------------------------------------------------------------------

#[rustler::nif(schedule = "DirtyCpu")]
fn plan_list_by_status(status: String) -> NifResult<String> {
    let conn = open_db().map_err(|e| rustler::Error::Term(Box::new(e)))?;
    let tasks = query_all_tasks(&conn).map_err(|e| rustler::Error::Term(Box::new(e)))?;
    let filtered: Vec<&Task> = if status == "all" {
        tasks.iter().collect()
    } else {
        tasks.iter().filter(|t| t.status == status).collect()
    };
    Ok(serde_json::to_string(&filtered).unwrap_or_else(|_| "[]".into()))
}

// ---------------------------------------------------------------------------
// NIF 4: plan_get_task — get single task by ID
// ---------------------------------------------------------------------------

#[rustler::nif(schedule = "DirtyCpu")]
fn plan_get_task(id: String) -> NifResult<String> {
    let conn = open_db().map_err(|e| rustler::Error::Term(Box::new(e)))?;
    let result: Result<Task, String> = execute_with_backoff(|| {
        conn.query_row(
            "SELECT Id, Title, Status, Priority, ParentId, Owner, Created \
             FROM Tasks WHERE Id = ?1",
            params![id],
            |row| {
                Ok(Task {
                    id: row.get(0)?,
                    title: row.get(1)?,
                    status: row.get(2)?,
                    priority: row.get(3)?,
                    parent_id: row.get(4)?,
                    owner: row.get(5)?,
                    created: row.get(6)?,
                })
            },
        )
    });
    match result {
        Ok(task) => Ok(serde_json::to_string(&task).unwrap_or_else(|_| "{}".into())),
        Err(e) => Ok(format!("{{\"error\":\"{}\"}}", e.replace('"', "\\\""))),
    }
}

// ---------------------------------------------------------------------------
// NIF 5: plan_add_task — insert new task
// ---------------------------------------------------------------------------

#[rustler::nif(schedule = "DirtyCpu")]
fn plan_add_task(title: String, priority: String) -> NifResult<String> {
    let conn = open_db().map_err(|e| rustler::Error::Term(Box::new(e)))?;
    let id = uuid::Uuid::new_v4()
        .to_string()
        .chars()
        .take(8)
        .collect::<String>();
    let created = chrono::Utc::now().to_rfc3339();

    let result: Result<usize, String> = execute_with_backoff(|| {
        conn.execute(
            "INSERT INTO Tasks (Id, Title, Status, Priority, Created, RawLines) \
             VALUES (?1, ?2, 'pending', ?3, ?4, ?5)",
            params![id, title, priority, created, ""],
        )
    });
    match result {
        Ok(_) => Ok(format!("{{\"ok\":true,\"id\":\"{}\"}}", id)),
        Err(e) => Ok(format!("{{\"ok\":false,\"error\":\"{}\"}}", e.replace('"', "\\\""))),
    }
}

// ---------------------------------------------------------------------------
// NIF 6: plan_update_task — update task status
// ---------------------------------------------------------------------------

#[rustler::nif(schedule = "DirtyCpu")]
fn plan_update_task(id: String, status: String) -> NifResult<String> {
    let valid = ["pending", "in_progress", "completed", "blocked"];
    if !valid.contains(&status.as_str()) {
        return Ok(format!(
            "{{\"ok\":false,\"error\":\"Invalid status '{}'. Valid: {:?}\"}}",
            status, valid
        ));
    }
    let conn = open_db().map_err(|e| rustler::Error::Term(Box::new(e)))?;
    let result: Result<usize, String> = execute_with_backoff(|| {
        conn.execute(
            "UPDATE Tasks SET Status = ?1 WHERE Id = ?2",
            params![status, id],
        )
    });
    match result {
        Ok(0) => Ok(format!("{{\"ok\":false,\"error\":\"Task {} not found\"}}", id)),
        Ok(_) => Ok(format!("{{\"ok\":true,\"id\":\"{}\",\"status\":\"{}\"}}", id, status)),
        Err(e) => Ok(format!("{{\"ok\":false,\"error\":\"{}\"}}", e.replace('"', "\\\""))),
    }
}

// ---------------------------------------------------------------------------
// NIF 7: plan_search — LIKE search on title
// ---------------------------------------------------------------------------

#[rustler::nif(schedule = "DirtyCpu")]
fn plan_search(query: String) -> NifResult<String> {
    let conn = open_db().map_err(|e| rustler::Error::Term(Box::new(e)))?;
    let pattern = format!("%{}%", query);
    let result: Result<Vec<Task>, String> = execute_with_backoff(|| {
        let mut stmt = conn.prepare(
            "SELECT Id, Title, Status, Priority, ParentId, Owner, Created \
             FROM Tasks WHERE Title LIKE ?1 ORDER BY Priority ASC, Created ASC \
             LIMIT 100",
        )?;
        let rows = stmt.query_map(params![pattern], |row| {
            Ok(Task {
                id: row.get(0)?,
                title: row.get(1)?,
                status: row.get(2)?,
                priority: row.get(3)?,
                parent_id: row.get(4)?,
                owner: row.get(5)?,
                created: row.get(6)?,
            })
        })?;
        let mut tasks = Vec::new();
        for r in rows {
            tasks.push(r?);
        }
        Ok(tasks)
    });
    match result {
        Ok(tasks) => Ok(serde_json::to_string(&tasks).unwrap_or_else(|_| "[]".into())),
        Err(e) => Ok(format!("{{\"error\":\"{}\"}}", e.replace('"', "\\\""))),
    }
}
