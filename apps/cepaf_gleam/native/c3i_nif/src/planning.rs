//! Planning NIFs — SQLite task management for BEAM/Gleam MCP.
//!
//! Direct port from planning_nif. 7 NIFs reading/writing Smriti.db.
//!
//! STAMP: SC-TODO-001, SC-ARCH-SPLIT-003, SC-NIF-001, SC-ZMOF-005

use crate::db::{execute_with_backoff, open_db};
use rusqlite::params;
use rustler::NifResult;
use serde::Serialize;

#[derive(Debug, Serialize)]
pub struct Task {
    pub id: String,
    pub title: String,
    pub status: String,
    pub priority: String,
    pub parent_id: Option<String>,
    pub owner: Option<String>,
    pub created: String,
}

#[derive(Debug, Serialize)]
struct StatusCounts {
    active: usize,
    pending: usize,
    completed: usize,
    blocked: usize,
    total: usize,
}

fn query_all_tasks(conn: &rusqlite::Connection) -> Result<Vec<Task>, String> {
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

#[rustler::nif(schedule = "DirtyCpu")]
pub fn plan_status() -> NifResult<String> {
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

#[rustler::nif(schedule = "DirtyCpu")]
pub fn plan_list_pending() -> NifResult<String> {
    let conn = open_db().map_err(|e| rustler::Error::Term(Box::new(e)))?;
    let tasks = query_all_tasks(&conn).map_err(|e| rustler::Error::Term(Box::new(e)))?;
    let pending: Vec<&Task> = tasks.iter().filter(|t| t.status != "completed").collect();
    Ok(serde_json::to_string(&pending).unwrap_or_else(|_| "[]".into()))
}

#[rustler::nif(schedule = "DirtyCpu")]
pub fn plan_list_by_status(status: String) -> NifResult<String> {
    let conn = open_db().map_err(|e| rustler::Error::Term(Box::new(e)))?;
    let tasks = query_all_tasks(&conn).map_err(|e| rustler::Error::Term(Box::new(e)))?;
    let filtered: Vec<&Task> = if status == "all" {
        tasks.iter().collect()
    } else {
        tasks.iter().filter(|t| t.status == status).collect()
    };
    Ok(serde_json::to_string(&filtered).unwrap_or_else(|_| "[]".into()))
}

#[rustler::nif(schedule = "DirtyCpu")]
pub fn plan_get_task(id: String) -> NifResult<String> {
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

#[rustler::nif(schedule = "DirtyCpu")]
pub fn plan_add_task(title: String, priority: String) -> NifResult<String> {
    // SC-TRUTH-001 / SC-VALUE-GUARD-001 — enum gate at L1 NIF boundary.
    // Mirrors the gate plan_update_task enforces (line 145).
    // Defense-in-depth: planning_daemon::db::add_task is the L3 gate, this is L1.
    let valid = ["P0", "P1", "P2", "P3"];
    if !valid.contains(&priority.as_str()) {
        return Ok(format!(
            "{{\"ok\":false,\"error\":\"Invalid priority '{}'. Valid: {:?}\"}}",
            priority, valid
        ));
    }
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
        Err(e) => Ok(format!(
            "{{\"ok\":false,\"error\":\"{}\"}}",
            e.replace('"', "\\\"")
        )),
    }
}

#[rustler::nif(schedule = "DirtyCpu")]
pub fn plan_update_task(id: String, status: String) -> NifResult<String> {
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
        Ok(0) => Ok(format!(
            "{{\"ok\":false,\"error\":\"Task {} not found\"}}",
            id
        )),
        Ok(_) => Ok(format!(
            "{{\"ok\":true,\"id\":\"{}\",\"status\":\"{}\"}}",
            id, status
        )),
        Err(e) => Ok(format!(
            "{{\"ok\":false,\"error\":\"{}\"}}",
            e.replace('"', "\\\"")
        )),
    }
}

#[rustler::nif(schedule = "DirtyCpu")]
pub fn plan_search(query: String) -> NifResult<String> {
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
